@echo off
REM Lanzador del Asistente Backrest. Se auto-eleva a administrador
REM (necesario para el config.json en systemprofile y para la tarea Backrest).
setlocal
net session >nul 2>&1
if %errorlevel% NEQ 0 (
    echo Solicitando permisos de administrador...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
title Asistente SQL + Backrest
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0AsistenteBackrest.ps1"
echo.
echo ------------------------------------------------------------
echo  El asistente termino. Podes cerrar esta ventana.
echo ------------------------------------------------------------
pause
