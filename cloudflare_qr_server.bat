@echo off
title Public Web Server via Cloudflare

:: Set the console to UTF-8 to correctly display characters like emojis.
chcp 65001 >nul

:: --- Configuration ---
set PORT=8765
set LOGFILE=%TEMP%\cloudflared_%RANDOM%.log


:: --- Prerequisite Checks ---
where python >nul 2>&1 || (echo ERROR: Python is not in your PATH. && pause && exit /b)
where cloudflared >nul 2>&1 || (echo ERROR: 'cloudflared' is not in your PATH. && pause && exit /b)
where qr >nul 2>&1 || (echo ERROR: The 'qrcode' library is not installed or not in your PATH. Run: pip install qrcode[pil] && pause && exit /b)


:: --- Main Script ---
cd /d "%~dp0"
cls
echo ===============================================
echo    🚀 Launching Servers...
echo ===============================================
echo.

:: 1. Start the local Python server in a new, minimized window.
echo [1/3] Starting local HTTP server on port %PORT%...
start "Local Python Server" /min python -m http.server %PORT%
echo       Done.
echo.

:: 2. Start the Cloudflare tunnel in the background.
echo [2/3] Starting Cloudflare tunnel...
if exist %LOGFILE% del %LOGFILE%
start "Cloudflare Tunnel" /b cloudflared tunnel --url http://localhost:%PORT% > %LOGFILE% 2>&1

:: 3. Wait for the tunnel to publish its public URL, with a 30-second timeout.
echo       Waiting for the public URL to be generated...
echo.
set RETRY_COUNT=0
:FindURL
set /a RETRY_COUNT+=1
if %RETRY_COUNT% gtr 15 (
    cls
    echo ===============================================
    echo   ❌ ERROR: Timed out waiting for Cloudflare.
    echo ===============================================
    echo.
    echo   Could not get a public URL after 30 seconds.
    echo   Please check the log file for errors:
    echo   %LOGFILE%
    echo.
    type %LOGFILE%
    pause
    goto cleanup
)

:: NEW: Check for an explicit error from Cloudflare first.
findstr /C:"ERR" /C:"failed" /C:"error=" %LOGFILE% >nul
if %errorlevel%==0 (
    cls
    echo ===============================================
    echo   ❌ ERROR: Cloudflare reported an error.
    echo ===============================================
    echo.
    echo   The cloudflared tool could not start the tunnel.
    echo   Here are the details from the log:
    echo.
    type %LOGFILE%
    pause
    goto cleanup
)


findstr /C:".trycloudflare.com" %LOGFILE% >nul
if %errorlevel%==1 (
    echo       Still waiting... (Attempt %RETRY_COUNT%/15)
    timeout /t 2 /nobreak >nul
    goto FindURL
)

echo       Success! URL has been captured.
echo.
:: Robustly parse the URL from the log file by searching for the token that starts with "https://"
for /f "tokens=*" %%a in ('findstr .trycloudflare.com %LOGFILE%') do (
    for %%b in (%%a) do (
        echo "%%b" | findstr /R /C:"^\"https://" >nul && set "TUNNEL_URL=%%b"
    )
)

if not defined TUNNEL_URL (
    echo ERROR: Found the line in the log, but could not parse the URL. This is unexpected.
    pause
    goto cleanup
)

:: --- Display Final Information ---
cls
echo ===============================================
echo    ✅ Your Server is LIVE
echo ===============================================
echo.
echo   Local Server: http://localhost:%PORT%
echo   Public URL:   %TUNNEL_URL%
echo.
echo   Scan the QR code below for the public URL:
echo.

qr "%TUNNEL_URL%"

echo.
echo ===============================================
echo. 
echo   The server is running. To stop everything,
echo   simply close this command window.
echo.

pause >nul

:cleanup
if exist %LOGFILE% del %LOGFILE% >nul 2>&1

