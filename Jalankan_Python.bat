@echo off
setlocal
title Transkripsi Video Hybrid - Python GUI
cd /d "%~dp0"

:: Konfigurasi encoding UTF-8 untuk konsol dan Python
chcp 65001 >nul
set "PYTHONIOENCODING=utf-8"
set "PYTHONUTF8=1"

echo ======================================================================
echo    MEMULAI APLIKASI TRANSKRIPSI VIDEO (PYTHON GUI)
echo ======================================================================
echo.

:: 1. Periksa ketersediaan Python
where python >nul 2>&1
if not errorlevel 1 goto python_ok

echo [!] Python belum terpasang atau belum terdaftar di PATH.
echo     Silakan unduh Python dari https://www.python.org/downloads/
echo     dan pastikan mencentang "Add Python to PATH".
echo.
pause
exit /b 1

:python_ok
for /f "tokens=*" %%V in ('python --version 2^>nul') do set "PY_VER=%%V"
echo [OK] Python ditemukan: %PY_VER%

:: 2. Tambahkan folder tools (FFmpeg) ke PATH
set "PATH=%~dp0tools;%PATH%"
if exist "%~dp0tools\ffmpeg.exe" (
    echo [OK] FFmpeg lokal siap: %~dp0tools\ffmpeg.exe
)

:: 3. Periksa dan pasang modul yang diperlukan
echo [*] Memeriksa dependensi Python (vosk, SpeechRecognition)...
python -m pip install vosk SpeechRecognition --quiet

:: 4. Jalankan aplikasi GUI
echo [*] Memulai antarmuka grafis Python...
python "python\transkripsi_gui.py"
if errorlevel 1 (
    echo.
    echo [!] Terjadi kesalahan saat menjalankan aplikasi Python (Kode: %errorlevel%).
    pause
)
