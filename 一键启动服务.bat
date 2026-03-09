@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"
title Codex Overview - Start Service

set "APP_ROOT=%CD%"
set "BIN_DIR=%APP_ROOT%\bin"
set "WEB_DIR=%APP_ROOT%\web"
set "LOG_DIR=%APP_ROOT%\logs"
set "SERVER_EXE=%BIN_DIR%\codex-overview-server.exe"
set "PID_FILE=%APP_ROOT%\.backend.pid"
set "PORT=8787"
set "SERVICE_URL=http://127.0.0.1:%PORT%"
set "HEALTH_URL=%SERVICE_URL%/api/health"

call :print_header
call :ensure_dir "%LOG_DIR%"

if not exist "%SERVER_EXE%" (
  echo [ERROR] Backend executable was not found.
  echo [INFO] Expected file: %SERVER_EXE%
  goto :error
)

if not exist "%WEB_DIR%\dist\index.html" (
  echo [ERROR] Frontend build output was not found.
  echo [INFO] Expected file: %WEB_DIR%\dist\index.html
  goto :error
)

call :check_running
if defined RUNNING_PID (
  echo [INFO] The service is already running.
  echo [INFO] PID: !RUNNING_PID!
  echo [INFO] URL: %SERVICE_URL%
  start "" "%SERVICE_URL%"
  call :hold_success
  exit /b 0
)

echo [STEP 1/3] Starting the backend service.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p = Start-Process -FilePath '%SERVER_EXE%' -ArgumentList '-open-browser=false -workspace-root ""%APP_ROOT%"" -static-dir ""%WEB_DIR%\dist""' -WorkingDirectory '%BIN_DIR%' -WindowStyle Hidden -RedirectStandardOutput '%LOG_DIR%\server.out.log' -RedirectStandardError '%LOG_DIR%\server.err.log' -PassThru; Set-Content -Path '%PID_FILE%' -Value $p.Id -Encoding ascii"
if errorlevel 1 (
  echo [ERROR] Failed to start the backend process.
  goto :error
)

echo [STEP 2/3] Waiting for the health check.
set "READY="
for /L %%I in (1,1,30) do (
  powershell -NoProfile -Command "try { $r = Invoke-WebRequest -UseBasicParsing '%HEALTH_URL%' -TimeoutSec 2; if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 500) { exit 0 } else { exit 1 } } catch { exit 1 }" >nul 2>nul
  if not errorlevel 1 (
    set "READY=1"
    goto :ready
  )
  timeout /t 1 >nul
)

:ready
if not defined READY (
  echo [ERROR] The service did not become ready in time.
  echo [INFO] Check these log files for details:
  echo        %LOG_DIR%\server.out.log
  echo        %LOG_DIR%\server.err.log
  goto :error
)

set "RUNNING_PID="
if exist "%PID_FILE%" set /p RUNNING_PID=<"%PID_FILE%"
echo [STEP 3/3] Service started successfully.
if defined RUNNING_PID echo [INFO] PID: !RUNNING_PID!
echo [INFO] URL: %SERVICE_URL%
echo [INFO] Opening the browser once.
start "" "%SERVICE_URL%"
call :hold_success
exit /b 0

:ensure_dir
if not exist "%~1" mkdir "%~1"
exit /b 0

:check_running
set "RUNNING_PID="
if exist "%PID_FILE%" (
  set /p RUNNING_PID=<"%PID_FILE%"
  if defined RUNNING_PID (
    tasklist /FI "PID eq !RUNNING_PID!" | findstr /I /C:"!RUNNING_PID!" >nul 2>nul
    if not errorlevel 1 exit /b 0
  )
  del "%PID_FILE%" >nul 2>nul
)
for /f "tokens=5" %%P in ('netstat -ano ^| findstr /R /C:":%PORT% .*LISTENING"') do (
  set "RUNNING_PID=%%P"
  >"%PID_FILE%" echo %%P
  exit /b 0
)
exit /b 0

:hold_success
echo.
echo This window will close automatically in 6 seconds.
timeout /t 6 >nul
exit /b 0

:error
echo.
echo Press any key to close this window.
pause >nul
exit /b 1

:print_header
echo ==========================================
echo Codex Overview - Start Service
echo ==========================================
echo.
exit /b 0
