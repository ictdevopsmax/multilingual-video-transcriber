@echo off
setlocal
title Transkripsi Video Hybrid - Java Swing GUI
cd /d "%~dp0"

echo ======================================================================
echo    MEMULAI APLIKASI TRANSKRIPSI VIDEO (JAVA SWING GUI)
echo ======================================================================
echo.

:: 1. Deteksi Java JDK
if defined JAVA_HOME goto check_java_home
if exist "C:\Program Files\Android\Android Studio\jbr\bin\java.exe" (
    set "JAVA_HOME=C:\Program Files\Android\Android Studio\jbr"
    goto check_java_home
)
if exist "C:\Program Files\Java" (
    for /d %%D in ("C:\Program Files\Java\jdk*") do (
        if exist "%%~D\bin\java.exe" set "JAVA_HOME=%%~D"
    )
)
if defined JAVA_HOME goto check_java_home
if exist "C:\Program Files\Eclipse Adoptium" (
    for /d %%D in ("C:\Program Files\Eclipse Adoptium\jdk*") do (
        if exist "%%~D\bin\java.exe" set "JAVA_HOME=%%~D"
    )
)
if defined JAVA_HOME goto check_java_home
if exist "C:\Program Files\Microsoft" (
    for /d %%D in ("C:\Program Files\Microsoft\jdk*") do (
        if exist "%%~D\bin\java.exe" set "JAVA_HOME=%%~D"
    )
)

:check_java_home
if defined JAVA_HOME (
    set "PATH=%JAVA_HOME%\bin;%PATH%"
    echo [OK] Menggunakan Java JDK dari: %JAVA_HOME%
    goto check_tools
)

where java >nul 2>&1
if not errorlevel 1 (
    echo [OK] Java ditemukan di PATH sistem.
    goto check_tools
)

echo [!] Java JDK belum terpasang di komputer ini.
echo     Silakan pasang Java JDK 17/21 atau gunakan GUI lain (Python / PowerShell / C#).
echo.
pause
exit /b 1

:check_tools
:: 2. Tambahkan tools (FFmpeg dan Maven) ke PATH
set "PATH=%~dp0tools;%PATH%"

if exist "%~dp0tools\apache-maven-3.9.9\bin\mvn.cmd" (
    set "PATH=%~dp0tools\apache-maven-3.9.9\bin;%PATH%"
)
if exist "%~dp0tools\maven\bin\mvn.cmd" (
    set "PATH=%~dp0tools\maven\bin;%PATH%"
)

:: 3. Periksa ketersediaan Maven
where mvn >nul 2>&1
if not errorlevel 1 goto run_app

echo [*] Mengunduh Apache Maven portable otomatis ke folder tools...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference = 'SilentlyContinue'; $zip = Join-Path '%~dp0tools' 'maven.zip'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; (New-Object Net.WebClient).DownloadFile('https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.9/apache-maven-3.9.9-bin.zip', $zip); Expand-Archive -Path $zip -DestinationPath (Join-Path '%~dp0tools' '') -Force; Remove-Item $zip -Force"

if exist "%~dp0tools\apache-maven-3.9.9\bin\mvn.cmd" (
    set "PATH=%~dp0tools\apache-maven-3.9.9\bin;%PATH%"
    echo [OK] Apache Maven portable berhasil dipasang.
    goto run_app
)

echo [!] Gagal memasang Maven otomatis.
pause
exit /b 1

:run_app
echo [OK] Apache Maven siap digunakan.
echo.
echo [*] Membangun dan menjalankan Transkripsi Video Java GUI...
cd /d "%~dp0java"
call mvn compile exec:java
if errorlevel 1 (
    echo.
    echo [!] Terjadi kesalahan saat menjalankan Java GUI.
    pause
)
