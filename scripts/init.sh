#!/usr/bin/env bash
# scripts/init.sh
# encoding: utf-8

########################################
# Strict Mode
########################################

set -Euo pipefail

########################################
# Metadata
########################################
# namespace: project.scripts.init

########################################
# Runtime Flags
########################################

DEBUG_MODE="${DEBUG_MODE:-false}"

if [[ "$DEBUG_MODE" == "true" ]]; then
    set -x
fi

########################################
# Detect source vs execution
########################################

function runtime.is_sourced() {
    [[ "${BASH_SOURCE[0]}" != "${0}" ]]
}

########################################
# Safe Exit
########################################

function runtime.safe_exit() {
    local code="${1:-0}"

    if runtime.is_sourced; then
        return "$code"
    else
        exit "$code"
    fi
}

########################################
# Logger
########################################

function logger.timestamp() {
    date +"%Y-%m-%d %H:%M:%S"
}

function logger.info() {
    echo "[INFO]  $(logger.timestamp) | $1"
}

function logger.warn() {
    echo "[WARN]  $(logger.timestamp) | $1"
}

function logger.error() {
    echo "[ERROR] $(logger.timestamp) | $1" >&2
}

########################################
# Stacktrace
########################################

function runtime.stacktrace() {
    logger.error "Stacktrace:"

    local i
    for ((i = 1; i < ${#FUNCNAME[@]}; i++)); do
        logger.error "  at ${FUNCNAME[$i]} (${BASH_SOURCE[$i]}:${BASH_LINENO[$((i - 1))]})"
    done
}

########################################
# Error Trap
########################################

function runtime.on_error() {
    local exit_code=$?
    runtime.stacktrace
    logger.error "Script aborted with exit code ${exit_code}"
    runtime.safe_exit "$exit_code"
}

trap runtime.on_error ERR

########################################
# Resolve project root (portable)
########################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

logger.info "Project root: $PROJECT_ROOT"

########################################
# System Dependency Validator
########################################

function system.require_command() {
    local cmd="$1"

    if ! command -v "$cmd" >/dev/null 2>&1; then
        logger.error "Required command not found: $cmd"
        runtime.safe_exit 1
    fi
}

########################################
# Validate base dependencies
########################################

function system.validate_base_dependencies() {
    system.require_command curl
    system.require_command python3
}

system.validate_base_dependencies

########################################
# Poetry Handling
########################################

POETRY_BIN_PATH="$HOME/.local/bin"

function poetry.exists() {
    command -v poetry >/dev/null 2>&1
}

function poetry.ensure_path() {
    export PATH="$POETRY_BIN_PATH:$PATH"
}

function poetry.install() {

    logger.info "Installing Poetry..."

    curl -sSL https://install.python-poetry.org | python3 -

    poetry.ensure_path

    if ! poetry.exists; then
        logger.error "Poetry installation failed"
        runtime.safe_exit 1
    fi
}

function poetry.ensure_installed() {

    if poetry.exists; then
        return
    fi

    poetry.install
}

poetry.ensure_installed

########################################
# Project Files
########################################

PYPROJECT_PATH="$PROJECT_ROOT/pyproject.toml"
REQUIREMENTS_PATH="$PROJECT_ROOT/requirements.txt"

########################################
# Ensure pyproject
########################################

function project.ensure_pyproject() {

    if [[ -f "$PYPROJECT_PATH" ]]; then
        return
    fi

    logger.warn "pyproject.toml not found"

    read -rp "Create pyproject.toml now? (s/n): " answer

    if [[ "$answer" =~ ^[sS]$ ]]; then
        poetry init -n --author "Richard <fozeds@github.com>"
    else
        logger.warn "User cancelled setup"
        runtime.safe_exit 0
    fi
}

project.ensure_pyproject

########################################
# Configure Poetry
########################################

function poetry.configure() {
    poetry config virtualenvs.in-project true --local
}

poetry.configure

########################################
# Install Dependencies
########################################

function poetry.install_dependencies() {
    logger.info "Running poetry install..."
    poetry install
}

poetry.install_dependencies

########################################
# Import requirements.txt
########################################

function poetry.import_requirements() {

    if [[ ! -f "$REQUIREMENTS_PATH" ]]; then
        return
    fi

    logger.info "Importing requirements.txt"

    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        poetry add "$line"
    done < "$REQUIREMENTS_PATH"
}

poetry.import_requirements

########################################
# Activate Virtualenv
########################################

function poetry.activate_virtualenv() {

    local venv_path
    venv_path="$(poetry env info --path)"

    if [[ -z "$venv_path" ]]; then
        logger.error "Virtualenv not found"
        return
    fi

    local activate_script="$venv_path/bin/activate"

    if [[ ! -f "$activate_script" ]]; then
        logger.error "Activate script not found"
        return
    fi

    if runtime.is_sourced; then
        logger.info "Activating virtualenv"
        # shellcheck disable=SC1090
        source "$activate_script"
        logger.info "Virtualenv activated"
    else
        logger.info "Run using: source scripts/init.sh to activate virtualenv"
    fi
}

poetry.activate_virtualenv

########################################
# Git Hooks
########################################

function git.setup_hooks() {

    local git_dir="$PROJECT_ROOT/.git"
    local source_hooks="$PROJECT_ROOT/scripts/git-hooks"
    local target_hooks="$git_dir/hooks"

    if [[ ! -d "$git_dir" ]]; then
        logger.warn "Git repository not found"
        return
    fi

    if [[ ! -d "$source_hooks" ]]; then
        logger.warn "No git hooks directory"
        return
    fi

    mkdir -p "$target_hooks"

    for hook in "$source_hooks"/*; do
        [[ -f "$hook" ]] || continue

        local target="$target_hooks/$(basename "$hook")"

        cp "$hook" "$target"
        chmod +x "$target"
    done

    logger.info "Git hooks configured"
}

git.setup_hooks

########################################
# Finish
########################################

logger.info "Setup completed successfully"
