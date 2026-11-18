@echo off
title Pasang FFmpeg Portable
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pasang_ffmpeg.ps1"
pause

