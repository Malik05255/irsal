# إرسال HAI

تطبيق مشاركة محلي بين **Android** و**Windows**. يكتشف الجهازين تلقائيًا عندما يكونان على نفس شبكة Wi‑Fi، ثم يرسل النصوص والصور والملفات مباشرة داخل الشبكة المحلية بدون خادم خارجي.

## المزايا الحالية

- اكتشاف تلقائي للأجهزة القريبة عبر الشبكة المحلية.
- اختيار تلقائي إذا ظهر جهاز واحد فقط.
- إرسال نص بضغطة زر.
- إرسال صورة أو ملف من Android أو Windows.
- استقبال مباشر وحفظ الملفات المستلمة.
- واجهة عربية RTL خفيفة ومتجاوبة للجوال والكمبيوتر.
- أيقونة مخصصة موحدة للتطبيقين.
- بناء Android APK وWindows x64 تلقائيًا من GitHub Actions.

## طريقة العمل

يستخدم التطبيق بث UDP محلي لاكتشاف نسخة **إرسال HAI** الأخرى، ثم ينقل المحتوى مباشرة بين عنواني الجهازين عبر اتصال محلي. الملفات لا تُرفع إلى خدمة سحابية أثناء النقل.

> يجب السماح للتطبيق بالاتصال بالشبكة الخاصة في Windows إذا ظهر تنبيه Windows Defender Firewall.

## التطوير

المشروع مبني بـ Flutter بحيث يشترك Android وWindows في نفس منطق النقل والواجهة الأساسية.

لبناء المنصات محليًا:

```bash
flutter create . --platforms=android,windows --project-name=irsal_hai --org=com.hai
python tools/generate_icon.py
flutter pub get
python tools/configure_platforms.py
dart run flutter_launcher_icons
```

ثم:

```bash
flutter build apk --release
flutter build windows --release
```
