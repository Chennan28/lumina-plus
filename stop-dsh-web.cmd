@echo off
setlocal
title DSH Web Stopper
echo Stopping DSH Web server (port 3080)...
powershell -NoProfile -Command "$p = Get-NetTCPConnection -LocalPort 3080 -State Listen -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -Unique; if ($p) { Stop-Process -Id $p -Force -ErrorAction SilentlyContinue; Write-Host ('DSH Web stopped (PID ' + $p + ').') } else { Write-Host 'DSH Web is not running.' }"
echo.
pause
endlocal
