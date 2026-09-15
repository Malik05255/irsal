import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PeerDevice {
  PeerDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.address,
    required this.port,
    required this.lastSeen,
  });

  final String id;
  final String name;
  final String platform;
  final String address;
  final int port;
  DateTime lastSeen;
}

class IncomingTransfer {
  const IncomingTransfer({
    required this.kind,
    required this.title,
    required this.detail,
    this.path,
    this.text,
  });

  final String kind;
  final String title;
  final String detail;
  final String? path;
  final String? text;
}

class LocalShareService {
  static const int discoveryPort = 45888;
  static const String protocol = 'irsal-hai-v1';

  final _peersController = StreamController<List<PeerDevice>>.broadcast();
  final _incomingController = StreamController<IncomingTransfer>.broadcast();
  final Map<String, PeerDevice> _peers = {};

  RawDatagramSocket? _discoverySocket;
  HttpServer? _server;
  Timer? _announceTimer;
  Timer? _pruneTimer;
  late String _deviceId;
  late String _deviceName;

  Stream<List<PeerDevice>> get peers => _peersController.stream;
  Stream<IncomingTransfer> get incoming => _incomingController.stream;

  Future<void> start() async {
    await _loadIdentity();
    await _startTransferServer();
    await _startDiscovery();
  }

  Future<void> _loadIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('device_id');
    if (id == null || id.isEmpty) {
      final random = Random.secure();
      final bytes = List<int>.generate(16, (_) => random.nextInt(256));
      id = base64UrlEncode(bytes).replaceAll('=', '');
      await prefs.setString('device_id', id);
    }
    _deviceId = id;

    final savedName = prefs.getString('device_name');
    if (savedName != null && savedName.trim().isNotEmpty) {
      _deviceName = savedName.trim();
    } else {
      final fallback = Platform.localHostname.trim();
      _deviceName = fallback.isEmpty ? (Platform.isWindows ? 'Windows' : 'Android') : fallback;
    }
  }

  Future<void> _startTransferServer() async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, 0, shared: true);
    _server!.listen(_handleRequest, onError: (_) {});
  }

  Future<void> _startDiscovery() async {
    _discoverySocket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      discoveryPort,
      reuseAddress: true,
    );
    _discoverySocket!.broadcastEnabled = true;
    _discoverySocket!.listen(_onDatagramEvent, onError: (_) {});

    _announce();
    _announceTimer = Timer.periodic(const Duration(seconds: 2), (_) => _announce());
    _pruneTimer = Timer.periodic(const Duration(seconds: 3), (_) => _prunePeers());
  }

  void _onDatagramEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final datagram = _discoverySocket?.receive();
    if (datagram == null) return;

    try {
      final raw = utf8.decode(datagram.data);
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['protocol'] != protocol) return;
      final id = data['id'] as String?;
      final port = data['port'] as int?;
      if (id == null || id == _deviceId || port == null) return;

      _peers[id] = PeerDevice(
        id: id,
        name: (data['name'] as String?)?.trim().isNotEmpty == true ? data['name'] as String : 'جهاز قريب',
        platform: (data['platform'] as String?) ?? 'unknown',
        address: datagram.address.address,
        port: port,
        lastSeen: DateTime.now(),
      );
      _emitPeers();
    } catch (_) {
      // Ignore unrelated UDP packets on the LAN.
    }
  }

  void _announce() {
    final socket = _discoverySocket;
    final server = _server;
    if (socket == null || server == null) return;

    final payload = utf8.encode(jsonEncode({
      'protocol': protocol,
      'id': _deviceId,
      'name': _deviceName,
      'platform': Platform.isWindows ? 'windows' : 'android',
      'port': server.port,
    }));

    try {
      socket.send(payload, InternetAddress('255.255.255.255'), discoveryPort);
    } catch (_) {}
  }

  void _prunePeers() {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 7));
    final before = _peers.length;
    _peers.removeWhere((_, peer) => peer.lastSeen.isBefore(cutoff));
    if (before != _peers.length) _emitPeers();
  }

  void _emitPeers() {
    final values = _peers.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _peersController.add(values);
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (request.method != 'POST') {
      request.response
        ..statusCode = HttpStatus.methodNotAllowed
        ..write('POST only');
      await request.response.close();
      return;
    }

    try {
      if (request.uri.path == '/send/text') {
        final bytes = <int>[];
        await for (final chunk in request) {
          bytes.addAll(chunk);
          if (bytes.length > 2 * 1024 * 1024) {
            throw const FormatException('Text payload too large');
          }
        }
        final text = utf8.decode(bytes);
        _incomingController.add(IncomingTransfer(
          kind: 'text',
          title: 'نص مستلم',
          detail: text.length > 90 ? '${text.substring(0, 90)}…' : text,
          text: text,
        ));
        request.response
          ..statusCode = HttpStatus.ok
          ..write('ok');
        await request.response.close();
        return;
      }

      if (request.uri.path == '/send/file') {
        final encodedName = request.headers.value('x-irsal-name');
        if (encodedName == null || encodedName.isEmpty) {
          throw const FormatException('Missing file name');
        }
        final decodedName = utf8.decode(base64Url.decode(encodedName));
        final safeName = _safeFileName(decodedName);
        final directory = await _receivedDirectory();
        final target = await _uniqueFile(directory, safeName);
        final sink = target.openWrite();
        await request.pipe(sink);

        _incomingController.add(IncomingTransfer(
          kind: 'file',
          title: 'ملف مستلم',
          detail: target.path,
          path: target.path,
        ));
        request.response
          ..statusCode = HttpStatus.ok
          ..write('ok');
        await request.response.close();
        return;
      }

      request.response
        ..statusCode = HttpStatus.notFound
        ..write('not found');
      await request.response.close();
    } catch (error) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('transfer failed: $error');
      await request.response.close();
    }
  }

  Future<void> sendText(PeerDevice peer, String text) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.postUrl(Uri.parse('http://${peer.address}:${peer.port}/send/text'));
      request.headers.contentType = ContentType('text', 'plain', charset: 'utf-8');
      request.add(utf8.encode(text));
      final response = await request.close();
      await response.drain<void>();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Receiver returned ${response.statusCode}');
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<void> sendFile(PeerDevice peer, File file, {String? displayName}) async {
    if (!await file.exists()) throw const FileSystemException('File does not exist');
    final length = await file.length();
    final name = displayName?.trim().isNotEmpty == true ? displayName!.trim() : file.uri.pathSegments.last;

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 7);
    try {
      final request = await client.postUrl(Uri.parse('http://${peer.address}:${peer.port}/send/file'));
      request.headers.set('x-irsal-name', base64Url.encode(utf8.encode(name)));
      request.contentLength = length;
      await request.addStream(file.openRead());
      final response = await request.close();
      await response.drain<void>();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Receiver returned ${response.statusCode}');
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<Directory> _receivedDirectory() async {
    Directory root;
    if (Platform.isWindows) {
      root = (await getDownloadsDirectory()) ?? await getApplicationDocumentsDirectory();
    } else {
      root = await getApplicationDocumentsDirectory();
    }
    final directory = Directory('${root.path}${Platform.pathSeparator}Irsal HAI');
    await directory.create(recursive: true);
    return directory;
  }

  Future<File> _uniqueFile(Directory directory, String name) async {
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    var candidate = File('${directory.path}${Platform.pathSeparator}$name');
    var index = 1;
    while (await candidate.exists()) {
      candidate = File('${directory.path}${Platform.pathSeparator}$base ($index)$ext');
      index++;
    }
    return candidate;
  }

  String _safeFileName(String input) {
    final trimmed = input.trim();
    final fallback = trimmed.isEmpty ? 'received_file' : trimmed;
    return fallback.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
  }

  Future<void> dispose() async {
    _announceTimer?.cancel();
    _pruneTimer?.cancel();
    _discoverySocket?.close();
    await _server?.close(force: true);
    await _peersController.close();
    await _incomingController.close();
  }
}
