@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0link_project.ps1"
exit /b %errorlevel%
