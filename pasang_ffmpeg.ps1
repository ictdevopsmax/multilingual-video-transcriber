<#
.SYNOPSIS
    Script otomatis untuk memasang atau mengunduh FFmpeg portable ke folder tools/
#>

$toolsDir = Join-Path $PSScriptRoot "tools"
$ffmpegExe = Join-Path $toolsDir "ffmpeg.exe"

if (Test-Path $ffmpegExe) {
    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host " [✓] FFmpeg portable SUDAH TERSEDIA dan SIAP DIGUNAKAN!   " -ForegroundColor Green
    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host "Lokasi File: $ffmpegExe" -ForegroundColor Cyan
    & $ffmpegExe -version | Select-Object -First 1
    Write-Host "`nAplikasi Transkripsi Video siap dijalankan." -ForegroundColor Green
    exit 0
}

Write-Host "=== PEMASANGAN FFMPEG PORTABLE OTOMATIS ===" -ForegroundColor Cyan
Write-Host "Mengecek paket WinGet atau unduhan lokal..." -ForegroundColor Yellow

New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null

# 1. Cek apakah winget sudah pernah mengunduhnya di AppData
$localAppData = $env:LOCALAPPDATA
if ($localAppData) {
    $wingetDir = Join-Path $localAppData "Microsoft\WinGet\Packages"
    if (Test-Path $wingetDir) {
        $found = Get-ChildItem -Path $wingetDir -Filter "ffmpeg.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
            Copy-Item -Path $found.FullName -Destination $ffmpegExe -Force
            Write-Host "[✓] Berhasil menemukan dan menyalin ffmpeg dari WinGet ke: $ffmpegExe" -ForegroundColor Green
            & $ffmpegExe -version | Select-Object -First 1
            exit 0
        }
    }
}

# 2. Pasang via winget jika belum ada
Write-Host "[+] Memasang FFmpeg via WinGet..." -ForegroundColor Yellow
winget install Gyan.FFmpeg --accept-package-agreements --accept-source-agreements

# Salin setelah instalasi winget
if ($localAppData) {
    $wingetDir = Join-Path $localAppData "Microsoft\WinGet\Packages"
    if (Test-Path $wingetDir) {
        $found = Get-ChildItem -Path $wingetDir -Filter "ffmpeg.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
            Copy-Item -Path $found.FullName -Destination $ffmpegExe -Force
            Write-Host "[✓] Berhasil memasang ffmpeg.exe ke: $ffmpegExe" -ForegroundColor Green
            & $ffmpegExe -version | Select-Object -First 1
            exit 0
        }
    }
}

Write-Host "`n[✓] Selesai." -ForegroundColor Green
