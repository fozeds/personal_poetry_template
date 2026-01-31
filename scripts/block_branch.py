# scripts/block_branch.py
import subprocess
import sys

branch = subprocess.check_output(
    ["git", "rev-parse", "--abbrev-ref", "HEAD"], encoding="utf-8"
).strip()

if branch in ("main", "master"):
    print(f'Commits diretos para "{branch}" não são permitidos.')
    sys.exit(1)
