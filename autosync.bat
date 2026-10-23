@echo off
cd /d "%~dp0"
echo Watching GitHub for updates... (close this window to stop)
:loop
git pull --quiet origin claude/serene-ritchie-ho5ke0
timeout /t 10 /nobreak >nul
goto loop