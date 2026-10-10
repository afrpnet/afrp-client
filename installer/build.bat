@echo off
setlocal

set ROOT=%~dp0..
set SRC=%ROOT%\build\windows\x64\runner\Release
set STAGE=%ROOT%\build\installer\staging
set OUT=%ROOT%\build\installer\output
set ISCC=D:\dev\innosetup\ISCC.exe

if not exist "%SRC%\afrp_oidc.exe" (
  echo [ERROR] Release build not found: %SRC%\afrp_oidc.exe
  echo         Run "flutter build windows --release" first.
  exit /b 1
)

if not exist "%ISCC%" (
  echo [ERROR] ISCC not found: %ISCC%
  exit /b 1
)

echo [1/4] Cleaning staging...
if exist "%STAGE%" rmdir /s /q "%STAGE%"
mkdir "%STAGE%"

echo [2/4] Copying release files...
xcopy /e /i /q /y "%SRC%" "%STAGE%" >nul
if errorlevel 1 (
  echo [ERROR] xcopy failed.
  exit /b 1
)

echo [3/4] Trimming non-Windows frpc payloads...
rmdir /s /q "%STAGE%\data\flutter_assets\assets\frpc\linux" 2>nul
rmdir /s /q "%STAGE%\data\flutter_assets\assets\frpc\macos" 2>nul
if not exist "%STAGE%\data\flutter_assets\assets\frpc\windows\frpc.exe" (
  echo [ERROR] Staging is missing the Windows frpc.exe payload.
  exit /b 1
)

echo [4/5] Compiling installer...
if not exist "%OUT%" mkdir "%OUT%"
"%ISCC%" "%~dp0setup.iss"
if errorlevel 1 (
  echo [ERROR] ISCC compilation failed.
  exit /b 1
)

echo [5/5] Packing portable zip...
for /f "tokens=3" %%v in ('findstr /b /c:"version:" "%ROOT%\pubspec.yaml"') do set APPVER=%%v
for /f "tokens=1 delims=+" %%v in ("%APPVER%") do set APPVER=%%v
set PORTABLE=%OUT%\afrp-oidc-client_%APPVER%_windows_amd64_portable.zip
if exist "%PORTABLE%" del /q "%PORTABLE%"
tar -a -c -f "%PORTABLE%" -C "%STAGE%" .
if errorlevel 1 (
  echo [ERROR] Portable zip packing failed.
  exit /b 1
)

echo.
echo [OK] Installer:   %OUT%\afrp-oidc-client_%APPVER%_windows_amd64_setup.exe
echo [OK] Portable:    %PORTABLE%
exit /b 0
