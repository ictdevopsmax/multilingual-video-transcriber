@echo off
title Unduh Model Vosk Offline
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0unduh_model.ps1" %*
pause
