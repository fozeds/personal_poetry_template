# Executa o script que bloqueia commits na main ou master
py scripts/block_branch.py || exit 1

# Se não bloqueado, adiciona os arquivos modificados
py scripts/add_repo_path_header.py || exit 1
git add -u