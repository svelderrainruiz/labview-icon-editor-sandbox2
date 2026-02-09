@echo off
where gk >nul 2>&1
if errorlevel 1 (
  echo GitKraken CLI 'gk' not found. Install it or add it to PATH.
  exit /b 1
)
gk git %*
