@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0publish_site_release.ps1" %*
exit /b %errorlevel%
