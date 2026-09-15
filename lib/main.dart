import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'local_share_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const IrsalHaiApp());
}

class IrsalHaiApp extends StatelessWidget {
  const IrsalHaiApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF2F6BFF);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'إرسال HAI',
      locale: const Locale('ar'),
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
          surface: const Color(0xFFF8FAFF),
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F7FC),
        cardTheme: const CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: Colors.white,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF3F6FC),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: HomeScreen(),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final LocalShareService _service = LocalShareService();
  StreamSubscription<IncomingTransfer>? _incomingSubscription;
  String? _selectedPeerId;
  bool _starting = true;
  bool _sending = false;
  String? _startupError;

  @override
  void initState() {
    super.initState();
    _incomingSubscription = _service.incoming.listen(_handleIncoming);
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      await _service.start();
    } catch (error) {
      _startupError = '$error';
    }
    if (mounted) setState(() => _starting = false);
  }

  void _handleIncoming(IncomingTransfer transfer) {
    if (!mounted) return;
    if (transfer.kind == 'text' && transfer.text != null) {
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('وصل نص جديد'),
          content: SelectableText(transfer.text!),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: transfer.text!));
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Text('نسخ'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('تم'),
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم استلام الملف وحفظه في:\n${transfer.path ?? transfer.detail}')),
      );
    }
  }

  PeerDevice? _selectedPeer(List<PeerDevice> peers) {
    if (_selectedPeerId == null) return null;
    for (final peer in peers) {
      if (peer.id == _selectedPeerId) return peer;
    }
    return null;
  }

  void _autoSelect(List<PeerDevice> peers) {
    if (peers.length == 1 && _selectedPeerId != peers.first.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedPeerId = peers.first.id);
      });
    } else if (_selectedPeerId != null && !peers.any((p) => p.id == _selectedPeerId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedPeerId = null);
      });
    }
  }

  Future<void> _sendText(PeerDevice peer) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إرسال نص'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 4,
          maxLines: 8,
          decoration: const InputDecoration(hintText: 'اكتب أو الصق النص هنا'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('إرسال'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text.isEmpty) return;
    await _runSend(() => _service.sendText(peer, text), 'تم إرسال النص');
  }

  Future<void> _pickAndSend(PeerDevice peer, FileType type) async {
    final result = await FilePicker.platform.pickFiles(type: type, allowMultiple: false);
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.single;
    final path = picked.path;
    if (path == null) {
      _showMessage('تعذر الوصول إلى مسار الملف المختار.');
      return;
    }
    await _runSend(
      () => _service.sendFile(peer, File(path), displayName: picked.name),
      type == FileType.image ? 'تم إرسال الصورة' : 'تم إرسال الملف',
    );
  }

  Future<void> _runSend(Future<void> Function() task, String success) async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      await task();
      _showMessage(success);
    } catch (error) {
      _showMessage('فشل الإرسال: $error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  void dispose() {
    _incomingSubscription?.cancel();
    unawaited(_service.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        titleSpacing: 20,
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _AppMark(),
            SizedBox(width: 10),
            Text('إرسال HAI', style: TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
      body: SafeArea(
        child: StreamBuilder<List<PeerDevice>>(
          stream: _service.peers,
          initialData: const [],
          builder: (context, snapshot) {
            final peers = snapshot.data ?? const <PeerDevice>[];
            _autoSelect(peers);
            final selected = _selectedPeer(peers);
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                  children: [
                    _StatusCard(
                      starting: _starting,
                      error: _startupError,
                      deviceCount: peers.length,
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'الأجهزة القريبة',
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 10),
                    if (!_starting && peers.isEmpty)
                      const _EmptyPeersCard()
                    else
                      ...peers.map(
                        (peer) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _PeerTile(
                            peer: peer,
                            selected: peer.id == _selectedPeerId,
                            onTap: () => setState(() => _selectedPeerId = peer.id),
                          ),
                        ),
                      ),
                    const SizedBox(height: 18),
                    Text(
                      selected == null ? 'اختر جهازًا للإرسال' : 'إرسال إلى ${selected.name}',
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 12),
                    _ActionGrid(
                      enabled: selected != null && !_sending,
                      busy: _sending,
                      onText: selected == null ? null : () => _sendText(selected),
                      onImage: selected == null ? null : () => _pickAndSend(selected, FileType.image),
                      onFile: selected == null ? null : () => _pickAndSend(selected, FileType.any),
                    ),
                    const SizedBox(height: 18),
                    const _PrivacyNote(),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AppMark extends StatelessWidget {
  const _AppMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: const Color(0xFF2F6BFF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.swap_horiz_rounded, color: Colors.white, size: 25),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.starting, required this.error, required this.deviceCount});

  final bool starting;
  final String? error;
  final int deviceCount;

  @override
  Widget build(BuildContext context) {
    final online = !starting && error == null;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF0FF),
                borderRadius: BorderRadius.circular(17),
              ),
              child: Icon(
                Platform.isWindows ? Icons.desktop_windows_rounded : Icons.smartphone_rounded,
                color: const Color(0xFF2F6BFF),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    starting ? 'جارٍ تشغيل الاتصال المحلي…' : error != null ? 'تعذر بدء الاتصال' : 'جاهز للاستقبال',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    error ?? (deviceCount == 0 ? 'تأكد أن الجهاز الآخر على نفس شبكة Wi‑Fi.' : 'تم العثور على $deviceCount من الأجهزة.'),
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: online ? const Color(0xFF2FB66D) : Colors.orange,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyPeersCard extends StatelessWidget {
  const _EmptyPeersCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: const Padding(
        padding: EdgeInsets.all(22),
        child: Row(
          children: [
            Icon(Icons.wifi_find_rounded, color: Color(0xFF2F6BFF)),
            SizedBox(width: 12),
            Expanded(child: Text('لم يظهر جهاز آخر بعد. افتح إرسال HAI على الجهاز الآخر واتصل بنفس شبكة Wi‑Fi.')),
          ],
        ),
      ),
    );
  }
}

class _PeerTile extends StatelessWidget {
  const _PeerTile({required this.peer, required this.selected, required this.onTap});

  final PeerDevice peer;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFEAF0FF) : Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              Icon(peer.platform == 'windows' ? Icons.desktop_windows_rounded : Icons.smartphone_rounded),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(peer.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    Text(peer.platform == 'windows' ? 'Windows • متصل' : 'Android • متصل'),
                  ],
                ),
              ),
              Icon(selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  color: selected ? const Color(0xFF2F6BFF) : Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionGrid extends StatelessWidget {
  const _ActionGrid({
    required this.enabled,
    required this.busy,
    required this.onText,
    required this.onImage,
    required this.onFile,
  });

  final bool enabled;
  final bool busy;
  final VoidCallback? onText;
  final VoidCallback? onImage;
  final VoidCallback? onFile;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth >= 620;
        final buttons = [
          _ActionButton(icon: Icons.text_fields_rounded, label: 'نص', enabled: enabled, onTap: onText),
          _ActionButton(icon: Icons.image_rounded, label: 'صورة', enabled: enabled, onTap: onImage),
          _ActionButton(icon: Icons.insert_drive_file_rounded, label: 'ملف', enabled: enabled, onTap: onFile),
        ];
        if (horizontal) {
          return Row(
            children: [
              for (var i = 0; i < buttons.length; i++) ...[
                Expanded(child: buttons[i]),
                if (i != buttons.length - 1) const SizedBox(width: 12),
              ],
            ],
          );
        }
        return Column(
          children: [
            for (var i = 0; i < buttons.length; i++) ...[
              buttons[i],
              if (i != buttons.length - 1) const SizedBox(height: 10),
            ],
            if (busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
          ],
        );
      },
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.label, required this.enabled, required this.onTap});

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: enabled ? onTap : null,
      icon: Icon(icon, size: 26),
      label: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      ),
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.lock_outline_rounded, size: 19, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'النقل مباشر بين الجهازين داخل الشبكة المحلية ولا يحتاج رفع الملفات إلى خادم خارجي.',
            style: TextStyle(color: Colors.grey.shade700, height: 1.45),
          ),
        ),
      ],
    );
  }
}
