#!/usr/bin/env python3
import os
import subprocess
import argparse
from pathlib import Path
from pyinfra import config

SCRIPT_DIR = Path(__file__).resolve().parent
STAGES_DIR = SCRIPT_DIR / "stages"
INVENTORY = SCRIPT_DIR / "inventory.py"

def run_pyinfra(script_name, ssh_user=None, auto_approve=False):
    env = os.environ.copy()

    script_path = STAGES_DIR / script_name
    command = ["pyinfra"]
    if auto_approve:
        command.append("-y")
    if ssh_user:
        command.extend(['--user', ssh_user])

    command.extend([str(INVENTORY), str(script_path)])

    print(f"▶ Running: {' '.join(command)}")
    print()
    subprocess.run(command, cwd=STAGES_DIR, env=env, check=True)

def main():
    parser = argparse.ArgumentParser(description="Deploy reverse proxy stack")
    parser.add_argument("--fresh", action="store_true", help="Run full deployment including bootstrap setup")
    parser.add_argument("--auto-approve", action="store_true", help="Skip verification steps and automatically approve changes")
    args = parser.parse_args()

    if args.fresh:
        run_pyinfra("0-bootstrap.py", ssh_user="root", auto_approve=args.auto_approve)

    run_pyinfra("1-configure.py", auto_approve=args.auto_approve)

if __name__ == "__main__":
    main()
