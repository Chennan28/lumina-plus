@echo off
setlocal
title DSH Web Launcher

echo ============================================
echo    DSH Web Launcher
echo ============================================
echo.

echo [1/3] Checking if DSH Web is already running...
powershell -NoProfile -Command "try{$r=Invoke-WebRequest -UseBasicParsing -Uri http://127.0.0.1:3080 -TimeoutSec 2;$null=$r;exit 0}catch{exit 1}" >nul 2>&1
if not errorlevel 1 (
    echo       Already running, opening browser directly.
    goto open
)

echo [2/3] Starting DSH Web server (window minimized; close it to stop the server)...
start "DSH Web Server" /min cmd /c "cd /d %USERPROFILE% && npx -y @deepseek-ai/dsh web"

echo [3/3] Waiting for server to be ready (up to ~120 seconds)...
set /a tries=0
:waitloop
timeout /t 1 /nobreak >nul
powershell -NoProfile -Command "try{$r=Invoke-WebRequest -UseBasicParsing -Uri http://127.0.0.1:3080 -TimeoutSec 2;$null=$r;exit 0}catch{exit 1}" >nul 2>&1
if not errorlevel 1 goto open
set /a tries+=1
if %tries% geq 120 (
    echo       Timeout waiting for server, opening browser anyway...
    goto open
)
goto waitloop

:open
echo Opening Edge: http://127.0.0.1:3080
start "" msedge "http://127.0.0.1:3080"
if errorlevel 1 start "" "http://127.0.0.1:3080"
echo.
echo Done! The server keeps running in the minimized window.
echo Close that window to stop the server.
timeout /t 3 /nobreak >nul
endlocal
