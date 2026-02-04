#!/bin/bash
# scripts/init.sh
# encoding: utf-8

echo "Iniciando setup do ambiente..."

# =========================================
# Vai para a raiz do projeto
# =========================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT=$(realpath "$SCRIPT_DIR/..")
cd "$PROJECT_ROOT" || exit 1

echo "Diretório do projeto: $PROJECT_ROOT"

# =========================================
# Configuração do Poetry (Linux/MacOS)
# =========================================
POETRY_BIN_PATH="$HOME/.local/bin"
POETRY_EXE="$POETRY_BIN_PATH/poetry"

function test_poetry {
    test -f "$POETRY_EXE"
}

# =========================================
# Instala Poetry se necessário
# =========================================
if ! test_poetry; then
    echo "Poetry não encontrado. Instalando..."

    curl -sSL https://install.python-poetry.org | python3 -

    if ! test -d "$POETRY_BIN_PATH"; then
        mkdir -p "$POETRY_BIN_PATH"
    fi

    if ! echo "$PATH" | grep -q "$POETRY_BIN_PATH"; then
        echo "Adicionando Poetry ao PATH..."
        echo "export PATH=\"$POETRY_BIN_PATH:\$PATH\"" >> "$HOME/.bashrc"
        source "$HOME/.bashrc"
    fi

    echo "Poetry instalado com sucesso."
fi

# Garante que o Poetry esteja no PATH da sessão atual
if ! echo "$PATH" | grep -q "$POETRY_BIN_PATH"; then
    export PATH="$POETRY_BIN_PATH:$PATH"
fi

# =========================================
# Arquivos do projeto
# =========================================
PYPROJECT_PATH="$PROJECT_ROOT/pyproject.toml"
REQUIREMENTS_PATH="$PROJECT_ROOT/requirements.txt"

# =========================================
# Cria pyproject.toml se não existir
# =========================================
if [ ! -f "$PYPROJECT_PATH" ]; then
    echo "pyproject.toml não encontrado."

    read -p "Deseja criar um pyproject.toml agora? (s/n): " answer

    if [[ "$answer" =~ ^[sS]$ ]]; then
        echo "Iniciando poetry init..."
        poetry init -n
    else
        echo "Setup interrompido pelo usuário."
        exit 0
    fi
fi

# =========================================
# Configura Poetry para NÃO pacote
# =========================================
echo "Configurando Poetry (package-mode = false)..."
poetry config --local package-mode false

# =========================================
# Configura venv dentro do projeto
# =========================================
poetry config virtualenvs.in-project true

# =========================================
# Importa requirements.txt se existir
# =========================================
if [ -f "$REQUIREMENTS_PATH" ]; then
    echo "requirements.txt encontrado. Importando dependências..."

    while IFS= read -r line; do
        # Ignora linhas em branco ou comentários
        if [[ ! "$line" =~ ^#.* && -n "$line" ]]; then
            poetry add "$line"
        fi
    done < "$REQUIREMENTS_PATH"
fi

# =========================================
# Instala dependências
# =========================================
echo "Instalando dependências com poetry install..."
poetry install

# =========================================
# Ativa ambiente virtual
# =========================================
echo "Tentando ativar ambiente virtual do Poetry..."

VENV_PATH=$(poetry env info --path)

if [ -n "$VENV_PATH" ]; then
    ACTIVATE_SCRIPT="$VENV_PATH/bin/activate"

    if [ -f "$ACTIVATE_SCRIPT" ]; then
        echo "Ativando venv: $VENV_PATH"
        source "$ACTIVATE_SCRIPT"
        echo "Ambiente virtual ativado no terminal atual."
    else
        echo "Script de ativação não encontrado."
    fi
else
    echo "Não foi possível encontrar o ambiente virtual."
fi

# =========================================
# Git Hooks (local repository only)
# =========================================
echo "Configurando Git hooks locais..."

GIT_DIR="$PROJECT_ROOT/.git"
SOURCE_HOOKS_DIR="$PROJECT_ROOT/scripts/git-hooks"
TARGET_HOOKS_DIR="$GIT_DIR/hooks"

if [ ! -d "$GIT_DIR" ]; then
    echo ".git não encontrado."
    echo "Este projeto ainda não é um repositório Git."
    echo "Execute 'git init' e rode novamente este script (init.sh)."
    exit 1
fi

if [ ! -d "$SOURCE_HOOKS_DIR" ]; then
    echo "Diretório de hooks não encontrado: $SOURCE_HOOKS_DIR"
    echo "Nenhum hook foi instalado."
    exit 1
fi

if [ ! -d "$TARGET_HOOKS_DIR" ]; then
    echo "Criando diretório de hooks do Git..."
    mkdir -p "$TARGET_HOOKS_DIR"
fi

# Copia hooks
for HOOK in "$SOURCE_HOOKS_DIR"/*; do
    if [ -f "$HOOK" ]; then
        TARGET_PATH="$TARGET_HOOKS_DIR/$(basename "$HOOK")"

        if [ -f "$TARGET_PATH" ]; then
            echo "Sobrescrevendo hook existente: $(basename "$HOOK")"
        else
            echo "Instalando hook: $(basename "$HOOK")"
        fi

        cp "$HOOK" "$TARGET_PATH"
    fi
done

# Tenta marcar hooks como executáveis (Linux/MacOS)
if command -v chmod &>/dev/null; then
    echo "Marcando hooks como executáveis (chmod +x)..."
    chmod +x "$TARGET_HOOKS_DIR"/*
else
    echo "chmod não disponível. Ignorando ajuste de permissão."
    echo "No Git Bash ou sistemas Linux/Mac, isso normalmente não é um problema."
fi

echo "Git hooks configurados com sucesso."

echo "Setup concluído com sucesso."
