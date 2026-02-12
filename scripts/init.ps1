# scripts/init.ps1
# encoding: utf-8
# namespace: project.scripts.init

[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# =========================================
# Runtime Flags
# =========================================

if (-not $env:DEBUG_MODE) {
    $env:DEBUG_MODE = "false"
}

if ($env:DEBUG_MODE -eq "true") {
    Set-PSDebug -Trace 1
}

# =========================================
# Runtime Helpers
# =========================================

function Runtime:IsDotSourced {
    return ($MyInvocation.InvocationName -eq '.')
}

function Runtime:SafeExit([int]$Code = 0) {
    if (Runtime:IsDotSourced) {
        return
    }
    else {
        exit $Code
    }
}

# =========================================
# Logger
# =========================================

function Logger:Timestamp {
    return (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
}

function Logger:Info($Message) {
    Write-Host "[INFO ] $(Logger:Timestamp) | $Message"
}

function Logger:Warn($Message) {
    Write-Warning "[WARN ] $(Logger:Timestamp) | $Message"
}

function Logger:Error($Message) {
    Write-Error "[ERROR] $(Logger:Timestamp) | $Message"
}

# =========================================
# Stacktrace
# =========================================

function Runtime:Stacktrace {
    Logger:Error "Stacktrace:"
    Get-PSCallStack | ForEach-Object {
        Logger:Error "  at $($_.Command) ($($_.Location))"
    }
}

# =========================================
# Error Trap
# =========================================

trap {
    Runtime:Stacktrace
    Logger:Error $_
    Runtime:SafeExit 1
}

# =========================================
# Resolve Project Root
# =========================================

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Resolve-Path (Join-Path $ScriptDir "..")
Set-Location $ProjectRoot

Logger:Info "Project root: $ProjectRoot"

# =========================================
# Dependency Validation
# =========================================

function System:RequireCommand($Command) {

    if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) {
        Logger:Error "Required command not found: $Command"
        Runtime:SafeExit 1
    }
}

function System:ValidateBaseDependencies {
    System:RequireCommand "python"
    System:RequireCommand "Invoke-WebRequest"
}

System:ValidateBaseDependencies

# =========================================
# Poetry Handling
# =========================================

$PoetryBinPath = "$env:APPDATA\Python\Scripts"
$PoetryExe = Join-Path $PoetryBinPath "poetry.exe"

function Poetry:Exists {
    return (Test-Path $PoetryExe)
}

function Poetry:EnsurePath {
    if ($env:Path -notlike "*$PoetryBinPath*") {
        $env:Path += ";$PoetryBinPath"
    }
}

function Poetry:Install {

    Logger:Info "Installing Poetry..."

    Invoke-WebRequest https://install.python-poetry.org -UseBasicParsing |
        Select-Object -ExpandProperty Content |
        py -

    Poetry:EnsurePath

    if (-not (Poetry:Exists)) {
        Logger:Error "Poetry installation failed"
        Runtime:SafeExit 1
    }
}

function Poetry:EnsureInstalled {
    if (-not (Poetry:Exists)) {
        Poetry:Install
    }
}

Poetry:EnsureInstalled
Poetry:EnsurePath

# =========================================
# Project Files
# =========================================

$PyprojectPath = Join-Path $ProjectRoot "pyproject.toml"
$RequirementsPath = Join-Path $ProjectRoot "requirements.txt"

# =========================================
# Ensure pyproject
# =========================================

function Project:EnsurePyproject {

    if (Test-Path $PyprojectPath) {
        return
    }

    Logger:Warn "pyproject.toml not found"

    $answer = Read-Host "Create pyproject.toml now? (s/n)"

    if ($answer -match '^[sS]') {
        & $PoetryExe init -n
    }
    else {
        Logger:Warn "User cancelled setup"
        Runtime:SafeExit 0
    }
}

Project:EnsurePyproject

# =========================================
# Configure Poetry
# =========================================

function Poetry:Configure {
    & $PoetryExe config virtualenvs.in-project true --local
}

Poetry:Configure

# =========================================
# Install Dependencies
# =========================================

function Poetry:InstallDependencies {
    Logger:Info "Running poetry install..."
    & $PoetryExe install
}

Poetry:InstallDependencies

# =========================================
# Import requirements.txt
# =========================================

function Poetry:ImportRequirements {

    if (-not (Test-Path $RequirementsPath)) {
        return
    }

    Logger:Info "Importing requirements.txt"

    Get-Content $RequirementsPath |
        Where-Object { $_ -and -not $_.StartsWith('#') } |
        ForEach-Object {
            & $PoetryExe add $_
        }
}

Poetry:ImportRequirements

# =========================================
# Activate VirtualEnv
# =========================================

function Poetry:ActivateVirtualEnv {

    $venvPath = & $PoetryExe env info --path

    if (-not $venvPath) {
        Logger:Error "Virtualenv not found"
        return
    }

    $activateScript = Join-Path $venvPath "Scripts\Activate.ps1"

    if (-not (Test-Path $activateScript)) {
        Logger:Error "Activate script not found"
        return
    }

    if (Runtime:IsDotSourced) {
        Logger:Info "Activating virtualenv"
        . $activateScript
        Logger:Info "Virtualenv activated"
    }
    else {
        Logger:Info "Run using: . scripts/init.ps1 to activate virtualenv"
    }
}

Poetry:ActivateVirtualEnv

# =========================================
# Git Hooks
# =========================================

function Git:SetupHooks {

    $GitDir = Join-Path $ProjectRoot ".git"
    $SourceHooks = Join-Path $ProjectRoot "scripts\git-hooks"
    $TargetHooks = Join-Path $GitDir "hooks"

    if (-not (Test-Path $GitDir)) {
        Logger:Warn "Git repository not found"
        return
    }

    if (-not (Test-Path $SourceHooks)) {
        Logger:Warn "Git hooks directory not found"
        return
    }

    if (-not (Test-Path $TargetHooks)) {
        New-Item -ItemType Directory -Path $TargetHooks | Out-Null
    }

    Get-ChildItem $SourceHooks -File | ForEach-Object {

        $target = Join-Path $TargetHooks $_.Name
        Copy-Item $_.FullName $target -Force

        $chmod = Get-Command chmod -ErrorAction SilentlyContinue
        if ($chmod) {
            & chmod +x $target
        }
    }

    Logger:Info "Git hooks configured"
}

Git:SetupHooks

Logger:Info "Setup completed successfully"
