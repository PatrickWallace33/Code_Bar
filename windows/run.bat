@echo off
chcp 65001 >nul
title Uso IA (Code_Bar) - Windows Companion

echo ========================================================
echo   Uso IA (Code_Bar) - Inicializando Companion Windows
echo ========================================================
echo.

where python >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERRO] Python 3 não foi encontrado no PATH do sistema.
    echo Por favor, instale o Python em https://python.org e marque a opção
    echo "Add python.exe to PATH" durante a instalação.
    pause
    exit /b 1
)

cd /d "%~dp0"

if not exist "venv" (
    echo Criando ambiente virtual (venv)...
    python -m venv venv
    if %errorlevel% neq 0 (
        echo [ERRO] Falha ao criar o ambiente virtual venv.
        pause
        exit /b 1
    )
)

call venv\Scripts\activate.bat

python -c "import PySide6" 2>nul
if %errorlevel% neq 0 (
    echo Instalando dependências (PySide6)...
    pip install -r requirements.txt
    if %errorlevel% neq 0 (
        echo [ERRO] Falha ao instalar dependências.
        pause
        exit /b 1
    )
)

echo Iniciando Uso IA Code_Bar...
start "" pythonw code_bar.py

exit /b 0
