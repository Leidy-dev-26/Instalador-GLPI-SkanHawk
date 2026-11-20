
@echo off
title SkanHawk - Registro de activos GLPI
color 0B

echo ==========================================
echo       SKANHAWK - REGISTRO DE ACTIVOS
echo ==========================================
echo.

set "SCRIPT=%~dp0Registrar-Activo-GLPI-Fields.ps1"

if not exist "%SCRIPT%" (
    echo ERROR: No se encuentra el script:
    echo %SCRIPT%
    echo.
    pause
    exit /b 1
)

echo Comprobando permisos de administrador...

net session >nul 2>&1

if %errorlevel% neq 0 (
    echo Solicitando permisos de administrador...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo Iniciando registro de activo...
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"

echo.
echo ==========================================
echo          PROCESO FINALIZADO
echo ==========================================
pause
