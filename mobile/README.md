# Flutter app (Android)

This folder will contain the Flutter app.

## Why it’s not scaffolded yet

Flutter SDK is not installed or not on PATH on this machine (`flutter --version` failed).

## Install Flutter (Windows)

1. Install Flutter SDK and add `flutter/bin` to your PATH.
2. Install Android Studio + Android SDK.
3. Run `flutter doctor` and fix anything it reports.

Then scaffold the project using:

```powershell
cd mobile
..\scripts\bootstrap_mobile.ps1
```
