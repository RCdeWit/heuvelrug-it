import sys
from pathlib import Path


def find_project_root():
    current = Path(__file__).resolve().parent
    while current != current.parent:
        if (current / "configs").is_dir() or (current / ".git").is_dir() or (current / "pyproject.toml").is_file():
            return current
        current = current.parent
    print("Error: Could not find project root", file=sys.stderr)
    sys.exit(1)