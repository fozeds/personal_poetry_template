# Executa o script que bloqueia commits na main ou master
py scripts/block_branch.py

# Se não bloqueado, adiciona os arquivos modificados
py scripts/add_repo_path_header.py
git add -u