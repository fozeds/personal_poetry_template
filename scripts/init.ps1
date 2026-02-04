# scripts/init.ps1
# encoding: utf-8

[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

Write-Host "Iniciando setup do ambiente..."

# =========================================
# Vai para a raiz do projeto
# =========================================
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Resolve-Path "$ScriptDir\.."
Set-Location $ProjectRoot

Write-Host "Diretório do projeto: $ProjectRoot"

# =========================================
# Configuração do Poetry (Windows)
# =========================================
$PoetryBinPath = "$env:APPDATA\Python\Scripts"
$PoetryExe = "$PoetryBinPath\poetry.exe"

function Test-Poetry {
    Test-Path $PoetryExe
}

# =========================================
# Instala Poetry se necessário
# =========================================
if (-not (Test-Poetry)) {
    Write-Host "Poetry não encontrado. Instalando..."

    try {
        Invoke-WebRequest -Uri https://install.python-poetry.org -UseBasicParsing |
            Select-Object -ExpandProperty Content |
            py -

        if (-not ($env:Path -like "*$PoetryBinPath*")) {
            $env:Path += ";$PoetryBinPath"
        }

        Write-Host "Poetry instalado com sucesso."
    } catch {
        Write-Error "Falha ao instalar Poetry: $_"
        exit 1
    }
}

# Garante PATH na sessão atual
if (-not ($env:Path -like "*$PoetryBinPath*")) {
    $env:Path += ";$PoetryBinPath"
}

# =========================================
# Arquivos do projeto
# =========================================
$PyprojectPath   = Join-Path $ProjectRoot "pyproject.toml"
$RequirementsPath = Join-Path $ProjectRoot "requirements.txt"

# =========================================
# Cria pyproject.toml se não existir
# =========================================
if (-not (Test-Path $PyprojectPath)) {
    Write-Warning "pyproject.toml não encontrado."

    $answer = Read-Host "Deseja criar um pyproject.toml agora? (s/n)"

    if ($answer -match '^[sS]') {
        Write-Host "Iniciando poetry init..."
        & $PoetryExe init
    } else {
        Write-Host "Setup interrompido pelo usuário."
        exit 0
    }
}

# =========================================
# Configura Poetry para NÃO pacote
# =========================================
Write-Host "Configurando Poetry (package-mode = false)..."
& $PoetryExe config --local package-mode false

# =========================================
# Configura venv dentro do projeto
# =========================================
& $PoetryExe config virtualenvs.in-project true

# =========================================
# Importa requirements.txt se existir
# =========================================
if (Test-Path $RequirementsPath) {
    Write-Host "requirements.txt encontrado. Importando dependências..."

    $Requirements = Get-Content $RequirementsPath |
        Where-Object { $_ -and -not $_.StartsWith('#') }

    if ($Requirements.Count -gt 0) {
        & $PoetryExe add $Requirements
    }
}

# =========================================
# Instala dependências
# =========================================
Write-Host "Instalando dependências com poetry install..."
& $PoetryExe install

# =========================================
# Ativa ambiente virtual
# =========================================
Write-Host "Tentando ativar ambiente virtual do Poetry..."

$venvPath = & $PoetryExe env info --path

if ($venvPath) {
    $activateScript = Join-Path $venvPath "Scripts\Activate.ps1"

    if (Test-Path $activateScript) {
        Write-Host "Ativando venv: $venvPath"
        . $activateScript
        Write-Host "Ambiente virtual ativado no terminal atual."
    } else {
        Write-Warning "Script de ativação não encontrado."
    }
} else {
    Write-Warning "Não foi possível encontrar o ambiente virtual."
}

# =========================================
# Git Hooks (local repository only)
# =========================================

Write-Host "Configurando Git hooks locais..."

$GitDir = Join-Path $ProjectRoot ".git"
$SourceHooksDir = Join-Path $ProjectRoot "scripts\git-hooks"
$TargetHooksDir = Join-Path $GitDir "hooks"

if (-not (Test-Path $GitDir)) {
    Write-Warning ".git não encontrado."
    Write-Warning "Este projeto ainda não é um repositório Git."
    Write-Warning "Execute 'git init' e rode novamente este script (init.ps1)."
    return
}

if (-not (Test-Path $SourceHooksDir)) {
    Write-Warning "Diretório de hooks não encontrado: $SourceHooksDir"
    Write-Warning "Nenhum hook foi instalado."
    return
}

if (-not (Test-Path $TargetHooksDir)) {
    Write-Host "Criando diretório de hooks do Git..."
    New-Item -ItemType Directory -Path $TargetHooksDir | Out-Null
}

# Copia hooks
Get-ChildItem -Path $SourceHooksDir -File | ForEach-Object {
    $TargetPath = Join-Path $TargetHooksDir $_.Name

    if (Test-Path $TargetPath) {
        Write-Host "Sobrescrevendo hook existente: $($_.Name)"
    } else {
        Write-Host "Instalando hook: $($_.Name)"
    }

    Copy-Item -Path $_.FullName -Destination $TargetPath -Force
}

# Tenta marcar hooks como executáveis (Git Bash / MSYS)
$ChmodCommand = Get-Command chmod -ErrorAction SilentlyContinue

if ($ChmodCommand) {
    Write-Host "Marcando hooks como executáveis (chmod +x)..."

    Get-ChildItem -Path $TargetHooksDir -File | ForEach-Object {
        & chmod +x $_.FullName
    }
} else {
    Write-Host "chmod não disponível. Ignorando ajuste de permissão."
    Write-Host "No Git for Windows, isso normalmente não é um problema."
}

Write-Host "Git hooks configurados com sucesso."

Write-Host "Setup concluído com sucesso."
