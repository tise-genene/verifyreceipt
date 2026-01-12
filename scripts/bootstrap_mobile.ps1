$ErrorActionPreference = 'Stop'

$root = Resolve-Path "$PSScriptRoot\.."
$mobile = Join-Path $root 'mobile'
Set-Location $mobile

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw 'Flutter is not installed or not on PATH. Install Flutter, then re-run.'
}

if (-not (Test-Path 'pubspec.yaml')) {
  flutter create . --platforms=android --org com.verifyreceipt --project-name verifyreceipt
}

flutter pub add flutter_riverpod dio freezed_annotation json_annotation
flutter pub add mobile_scanner image_picker google_mlkit_text_recognition
flutter pub add hive hive_flutter path_provider
flutter pub add dev:build_runner dev:freezed dev:json_serializable

Write-Host 'Flutter project ready. Next: implement screens + API client.'
