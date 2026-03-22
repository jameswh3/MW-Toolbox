#!/usr/bin/env python3
"""
Pre-commit hook: strips outputs and execution counts from all staged Jupyter notebooks.
Clears cell outputs and re-stages the files so clean notebooks are what gets committed.
"""
import json
import subprocess
import sys
from pathlib import Path


def clear_notebook_outputs(path: Path) -> bool:
    """Clear outputs and execution counts in-place. Returns True if the file was modified."""
    text = path.read_text(encoding="utf-8")
    nb = json.loads(text)
    modified = False

    for cell in nb.get("cells", []):
        if cell.get("outputs"):
            cell["outputs"] = []
            modified = True
        if cell.get("execution_count") is not None:
            cell["execution_count"] = None
            modified = True

    if modified:
        # Write back using nbformat-compatible formatting (indent=1, trailing newline)
        path.write_text(
            json.dumps(nb, indent=1, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )

    return modified


def get_staged_notebooks() -> list[str]:
    result = subprocess.run(
        ["git", "diff", "--cached", "--name-only", "--diff-filter=ACM"],
        capture_output=True,
        text=True,
    )
    return [f for f in result.stdout.splitlines() if f.endswith(".ipynb")]


def get_repo_root() -> Path:
    result = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        capture_output=True,
        text=True,
    )
    return Path(result.stdout.strip())


def main() -> None:
    staged = get_staged_notebooks()
    if not staged:
        sys.exit(0)

    repo_root = get_repo_root()
    cleared = []

    for rel_path in staged:
        path = repo_root / rel_path
        if path.exists():
            if clear_notebook_outputs(path):
                cleared.append(rel_path)
                print(f"  cleared outputs: {rel_path}")
            else:
                print(f"  no outputs to clear: {rel_path}")

    if cleared:
        subprocess.run(["git", "add"] + cleared, check=True)


if __name__ == "__main__":
    main()
