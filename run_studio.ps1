$path = "pubspec.yaml"
if (-not (Test-Path $path)) {
    Write-Host "Erreur : pubspec.yaml introuvable !" -ForegroundColor Red
    exit 1
}

Write-Host ">> Lancement de Musicality Studio (ID: com.musicality.studio) sur votre Xiaomi..." -ForegroundColor Magenta
flutter run --release --dart-define=STUDIO_MODE=true
