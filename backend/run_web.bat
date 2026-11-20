@echo off
rem SmartCare website - double-click to run. Extra args are passed through, e.g. run_web.bat --lan
setlocal
cd /d "%~dp0"

where python >nul 2>nul
if errorlevel 1 (
  echo Python 3 is required: https://www.python.org/downloads/
  pause
  exit /b 1
)

python -m pip install --disable-pip-version-check -q -r requirements.txt
if errorlevel 1 (
  echo Failed to install requirements.
  pause
  exit /b 1
)

python run_web.py %*
pause
