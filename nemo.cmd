@echo off
setlocal DisableDelayedExpansion
set "NEMO_PS1=%~dp0nemo.ps1"
if not exist "%NEMO_PS1%" (
  echo nemo: cannot find nemo.ps1 next to nemo.cmd
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%NEMO_PS1%" %*
exit /b %ERRORLEVEL%
