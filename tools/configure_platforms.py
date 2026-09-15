from pathlib import Path
import re


def patch(path: Path, transform):
    if not path.exists():
        return
    old = path.read_text(encoding='utf-8')
    new = transform(old)
    if new != old:
        path.write_text(new, encoding='utf-8')
        print(f'Patched {path}')


manifest = Path('android/app/src/main/AndroidManifest.xml')

def patch_manifest(text: str) -> str:
    permissions = (
        '<uses-permission android:name="android.permission.INTERNET" />\n'
        '    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />\n'
        '    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />\n'
    )
    if 'android.permission.INTERNET' not in text:
        text = text.replace('<manifest xmlns:android="http://schemas.android.com/apk/res/android">',
                            '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n    ' + permissions)
    text = re.sub(r'android:label="[^"]*"', 'android:label="إرسال HAI"', text, count=1)
    if 'android:usesCleartextTraffic=' not in text:
        text = text.replace('<application', '<application\n        android:usesCleartextTraffic="true"', 1)
    return text

patch(manifest, patch_manifest)

# Keep targetSdk 36 for this LAN-transfer build. Android 17 only enforces
# ACCESS_LOCAL_NETWORK for apps targeting API 37+, while compileSdk 37 remains
# compatible with modern dependencies.
kts = Path('android/app/build.gradle.kts')

def patch_kts(text: str) -> str:
    text = re.sub(r'compileSdk\s*=\s*flutter\.compileSdkVersion', 'compileSdk = 37', text)
    text = re.sub(r'targetSdk\s*=\s*flutter\.targetSdkVersion', 'targetSdk = 36', text)
    text = re.sub(r'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 23', text)
    return text

patch(kts, patch_kts)

groovy = Path('android/app/build.gradle')

def patch_groovy(text: str) -> str:
    text = re.sub(r'compileSdk(?:Version)?\s+flutter\.compileSdkVersion', 'compileSdkVersion 37', text)
    text = re.sub(r'targetSdk(?:Version)?\s+flutter\.targetSdkVersion', 'targetSdkVersion 36', text)
    text = re.sub(r'minSdk(?:Version)?\s+flutter\.minSdkVersion', 'minSdkVersion 23', text)
    return text

patch(groovy, patch_groovy)

main_cpp = Path('windows/runner/main.cpp')

def patch_windows_title(text: str) -> str:
    text = text.replace('L"irsal_hai"', 'L"إرسال HAI"')
    text = text.replace('L"Irsal Hai"', 'L"إرسال HAI"')
    return text

patch(main_cpp, patch_windows_title)

runner_rc = Path('windows/runner/Runner.rc')

def patch_windows_metadata(text: str) -> str:
    for key in ('FileDescription', 'InternalName', 'OriginalFilename', 'ProductName'):
        text = re.sub(rf'VALUE "{key}", "[^"]*"', f'VALUE "{key}", "Irsal HAI"', text)
    return text

patch(runner_rc, patch_windows_metadata)
