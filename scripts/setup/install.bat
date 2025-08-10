@echo off
REM ============================================================================
REM DaVinci Resolve MCP Integration - One-step Installer (Windows, Batch)
REM - Per-run timestamped log via PowerShell (works on modern Win11)
REM - Fixed control flow (functions are below; we jump to :main)
REM - Robust quoting, ANSI colors, and error handling
REM ============================================================================

setlocal EnableExtensions EnableDelayedExpansion

REM ---------- ANSI colors ----------
for /F %%A in ('echo prompt $E^| cmd') do set "ESC=%%A"
set "C_GRN=%ESC%[92m"
set "C_YEL=%ESC%[93m"
set "C_BLU=%ESC%[94m"
set "C_RED=%ESC%[91m"
set "C_BLD=%ESC%[1m"
set "C_RST=%ESC%[0m"

REM ---------- Paths ----------
REM Resolve project root from this script location: scripts\setup\ -> project root is two levels up
for %%I in ("%~dp0..\..") do set "INSTALL_DIR=%%~fI"
set "VENV_DIR=%INSTALL_DIR%\venv"
set "LOGS_DIR=%INSTALL_DIR%\logs"
set "CURSOR_CONFIG_DIR=%APPDATA%\Cursor\mcp"
set "CURSOR_CONFIG_FILE=%CURSOR_CONFIG_DIR%\config.json"
set "PROJECT_CURSOR_DIR=%INSTALL_DIR%\.cursor"
set "PROJECT_CONFIG_FILE=%PROJECT_CURSOR_DIR%\mcp.json"

REM ---------- Get timestamp for a fresh log (no WMIC, use PowerShell) ----------
for /f %%I in ('powershell -NoProfile -Command "(Get-Date).ToString('yyyyMMdd_HHmmss')"') do set "LOG_TS=%%I"
if not exist "%LOGS_DIR%" mkdir "%LOGS_DIR%" >nul 2>&1
set "LOG_FILE=%LOGS_DIR%\install_%LOG_TS%.log"

REM ---------- Banner ----------
echo %C_BLU%%C_BLD%=================================================%C_RST%
echo %C_BLU%%C_BLD%  DaVinci Resolve MCP Integration Installer      %C_RST%
echo %C_BLU%%C_BLD%=================================================%C_RST%
echo %C_YEL%Installation directory:%C_RST% %INSTALL_DIR%
echo Log file: %LOG_FILE%
echo.

REM ---------- Init log ----------
> "%LOG_FILE%" (
  echo === DaVinci Resolve MCP Installation Log ===
  echo Date: %date% %time%
  echo Install directory (project root): %INSTALL_DIR%
  echo User: %USERNAME%
  echo System: %OS% %PROCESSOR_ARCHITECTURE%
  echo.
)

goto :main

:: ---------------------------------------------------------------------------
:: FUNCTIONS
:: ---------------------------------------------------------------------------

:log
REM usage: call :log "message"
>>"%LOG_FILE%" echo [%time%] %~1
exit /b 0

:say
REM safe echo for use inside blocks; usage: call :say "text"
REM Avoids parser issues with parentheses
echo(%~1
exit /b 0

:check_resolve_running
call :log "Checking if DaVinci Resolve is running"
echo %C_YEL%Checking if DaVinci Resolve is running...%C_RST%
tasklist /FI "IMAGENAME eq Resolve.exe" 2>nul | find /I "Resolve.exe" >nul
if errorlevel 1 (
  echo %C_RED%NOT RUNNING%C_RST%
  echo %C_YEL%Resolve is not running. Some integration checks will be skipped.%C_RST%
  call :log "Resolve not running (continuing)"
  set "RESOLVE_RUNNING=0"
) else (
  echo %C_GRN%OK%C_RST%
  call :log "Resolve is running"
  set "RESOLVE_RUNNING=1"
)
exit /b 0

:create_venv
call :log "Ensuring Python virtual environment"
echo %C_YEL%Setting up Python virtual environment...%C_RST%
if exist "%VENV_DIR%\Scripts\python.exe" (
  echo %C_GRN%OK%C_RST%
  call :log "Venv already exists"
  exit /b 0
)

python -V >nul 2>&1 || py -V >nul 2>&1
if errorlevel 1 (
  echo %C_RED%FAILED%C_RST%
  echo %C_RED%Python 3.9+ not found on PATH.%C_RST%
  call :log "Python not found on PATH"
  exit /b 1
)

python -m venv "%VENV_DIR%" >>"%LOG_FILE%" 2>&1 || py -m venv "%VENV_DIR%" >>"%LOG_FILE%" 2>&1
if errorlevel 1 (
  echo %C_RED%FAILED%C_RST%
  call :log "Venv creation failed"
  exit /b 1
)
echo %C_GRN%OK%C_RST%
call :log "Venv created"
exit /b 0

:install_mcp
call :log "Installing MCP SDK into venv"
echo %C_YEL%Installing MCP SDK...%C_RST%
set "PIP_EXE=%VENV_DIR%\Scripts\pip.exe"
if not exist "%PIP_EXE%" (
  echo %C_RED%FAILED%C_RST%
  call :log "pip.exe not found in venv"
  exit /b 1
)
"%PIP_EXE%" install --upgrade pip >>"%LOG_FILE%" 2>&1
"%PIP_EXE%" install "mcp[cli]" >>"%LOG_FILE%" 2>&1
  if exist "%INSTALL_DIR%\requirements.txt" (
    call :log "requirements.txt found; installing project dependencies"
    "%PIP_EXE%" install -r "%INSTALL_DIR%\requirements.txt" >>"%LOG_FILE%" 2>&1
  ) else (
    call :log "requirements.txt not found; skipping project dependency install"
  )
if errorlevel 1 (
  echo %C_RED%FAILED%C_RST%
  call :log "MCP SDK install failed"
  exit /b 1
)
echo %C_GRN%OK%C_RST%
call :log "MCP SDK installed"
exit /b 0

:setup_env_vars
call :log "Writing .env.bat and setting session vars"
echo %C_YEL%Setting up environment variables...%C_RST%
set "RESOLVE_SCRIPT_API=C:\ProgramData\Blackmagic Design\DaVinci Resolve\Support\Developer\Scripting"
set "RESOLVE_SCRIPT_LIB=C:\Program Files\Blackmagic Design\DaVinci Resolve\fusionscript.dll"
set "ENV_FILE=%INSTALL_DIR%\.env.bat"

> "%ENV_FILE%" (
  echo @echo off
  echo rem DaVinci Resolve Scripting
  echo set "RESOLVE_SCRIPT_API=%RESOLVE_SCRIPT_API%"
  echo set "RESOLVE_SCRIPT_LIB=%RESOLVE_SCRIPT_LIB%"
  echo set "PYTHONPATH=%%PYTHONPATH%%;%%RESOLVE_SCRIPT_API%%\Modules"
)

call "%ENV_FILE%"
if errorlevel 1 (
  echo %C_RED%FAILED%C_RST%
  call :log ".env.bat load failed"
  exit /b 1
)
echo %C_GRN%OK%C_RST%
call :log "ENV set (session)"
exit /b 0

:setup_cursor_config
call :log "Creating Cursor MCP configs"
echo %C_YEL%Setting up Cursor MCP configuration...%C_RST%
if not exist "%CURSOR_CONFIG_DIR%" mkdir "%CURSOR_CONFIG_DIR%" >nul 2>&1
if errorlevel 1 (
  echo %C_RED%FAILED%C_RST%
  call :log "Unable to create %CURSOR_CONFIG_DIR%"
  exit /b 1
)
if not exist "%PROJECT_CURSOR_DIR%" mkdir "%PROJECT_CURSOR_DIR%" >nul 2>&1

  set "PY_CMD=%INSTALL_DIR:\=\\%\\venv\\Scripts\\python.exe"
  set "SVR_CMD=%INSTALL_DIR:\=\\%\\src\\resolve_mcp_server.py"

> "%CURSOR_CONFIG_FILE%" (
  echo {
  echo   "mcpServers": {
  echo     "davinci-resolve": {
  echo       "name": "DaVinci Resolve MCP",
  echo       "command": "%PY_CMD%",
  echo       "args": ["%SVR_CMD%"]
  echo     }
  echo   }
  echo }
)

> "%PROJECT_CONFIG_FILE%" (
  echo {
  echo   "mcpServers": {
  echo     "davinci-resolve": {
  echo       "name": "DaVinci Resolve MCP",
  echo       "command": "%PY_CMD%",
  echo       "args": ["%SVR_CMD%"]
  echo     }
  echo   }
  echo }
)

if exist "%CURSOR_CONFIG_FILE%" if exist "%PROJECT_CONFIG_FILE%" (
  echo %C_GRN%OK%C_RST%
  call :log "Cursor configs written"
  exit /b 0
) else (
  echo %C_RED%FAILED%C_RST%
  call :log "Cursor config write failed"
  exit /b 1
)

:verify_installation
call :log "Running verification script"
echo %C_BLU%%C_BLD%=================================================%C_RST%
echo %C_YEL%%C_BLD%Verifying installation...%C_RST%
if not exist "%INSTALL_DIR%\scripts\verify-installation.bat" (
  call :log "verify-installation.bat not found, skipping"
  echo %C_YEL%No verification script found. Skipping.%C_RST%
  exit /b 0
)
call "%INSTALL_DIR%\scripts\verify-installation.bat"
set "VERIFY_RESULT=%ERRORLEVEL%"
call :log "Verification result: !VERIFY_RESULT!"
exit /b !VERIFY_RESULT!

:run_server
call :log "Starting server"
echo %C_BLU%%C_BLD%=================================================%C_RST%
echo %C_GRN%%C_BLD%Starting DaVinci Resolve MCP Server...%C_RST%
echo.
"%VENV_DIR%\Scripts\python.exe" "%INSTALL_DIR%\src\resolve_mcp_server.py"
set "SERVER_EXIT=%ERRORLEVEL%"
call :log "Server exited with code: !SERVER_EXIT!"
exit /b !SERVER_EXIT!

:: ---------------------------------------------------------------------------
:: MAIN
:: ---------------------------------------------------------------------------
:main
call :log "Starting installation process"

call :check_resolve_running

call :create_venv
if errorlevel 1 (
  call :log "Abort: venv setup failed"
  call :say "%C_RED%Installation aborted (venv).%C_RST%"
  exit /b 1
)

call :install_mcp
if errorlevel 1 (
  call :log "Abort: MCP SDK install failed"
    call :say "%C_RED%Installation aborted (MCP SDK).%C_RST%"
  exit /b 1
)

call :setup_env_vars
if errorlevel 1 (
  call :log "Abort: env var setup failed"
  call :say "%C_RED%Installation aborted (env).%C_RST%"
  exit /b 1
)

call :setup_cursor_config
if errorlevel 1 (
  call :log "Abort: Cursor config failed"
  call :say "%C_RED%Installation aborted (Cursor config).%C_RST%"
  exit /b 1
)

call :verify_installation
if errorlevel 1 (
  call :log "Completed with verification warnings"
  call :say "%C_YEL%Installation completed with warnings.%C_RST%"
    call :say "%C_YEL%Fix issues then re-run verification:%C_RST% scripts\\verify-installation.bat"
  exit /b 1
)

call :log "Installation completed successfully"
call :say "%C_GRN%%C_BLD%Installation completed successfully!%C_RST%"
call :say "%C_YEL%Start the server with:%C_RST% run-now.bat"
echo.
set /p START_SERVER="Do you want to start the server now? (y/n) "
if /I "%START_SERVER%"=="y" (
  call :run_server
) else (
  call :log "User chose not to start the server"
  echo %C_YEL%You can start later with:%C_RST% run-now.bat
)

exit /b 0
