# scripts/add_repo_path_header.py
#!/usr/bin/env python3
import subprocess
import sys
from pathlib import Path


def get_repo_root():
    try:
        return Path(
            subprocess.check_output(
                ["git", "rev-parse", "--show-toplevel"], text=True
            ).strip()
        )
    except subprocess.CalledProcessError:
        return Path.cwd()


def ensure_header(filepath, repo_root):
    path = Path(filepath).resolve()
    try:
        rel_path = path.relative_to(repo_root)
    except ValueError:
        rel_path = path.name
    header = f"# {rel_path.as_posix()}\n"

    with open(path, "r+", encoding="utf-8") as f:
        lines = f.readlines()

    # Se primeira linha já tem comentário, substitui; senão, adiciona
    if lines and lines[0].startswith("# "):
        if lines[0] != header:
            lines[0] = header
    else:
        lines.insert(0, header)

    with open(path, "w", encoding="utf-8") as f:
        f.writelines(lines)


def main():
    repo_root = get_repo_root()
    for file in sys.argv[1:]:
        if file.endswith(".py"):
            ensure_header(file, repo_root)
    return 0


if __name__ == "__main__":
    sys.exit(main())
