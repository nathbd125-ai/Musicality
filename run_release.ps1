$path = "pubspec.yaml"
if (-not (Test-Path $path)) {
    Write-Host "Erreur : pubspec.yaml introuvable !" -ForegroundColor Red
    exit 1
}

$content = [System.IO.File]::ReadAllText($path)
$content = [System.Text.RegularExpressions.Regex]::Replace($content, '(?m)^version:\s*(.*?)\+(\d+)\s*$', {
    param($match)
    $base = $match.Groups[1].Value
    $build = [int]$match.Groups[2].Value + 1
    Write-Host ">> Version incrementee avec succes : $base+$build" -ForegroundColor Cyan
    return "version: $base+$build"
})

[System.IO.File]::WriteAllText($path, $content, [System.Text.Encoding]::UTF8)

Write-Host ">> Lancement de flutter run --release..." -ForegroundColor Green
flutter run --release
