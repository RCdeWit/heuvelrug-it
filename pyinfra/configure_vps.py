#!/usr/bin/env python3
import os
import subprocess
import argparse
from pathlib import Path
from pyinfra import config

SCRIPT_DIR = Path(__file__).resolve().parent
STAGES_DIR = SCRIPT_DIR / "stages"
INVENTORY = SCRIPT_DIR / "inventory.py"

STAGES = [
    ("0-bootstrap", "0-bootstrap.py", "root"),
    ("1-system", "1-system.py", None),
    ("2-docker", "2-docker.py", None),
    ("3-caddy", "3-caddy.py", None),
]

def get_stage_names():
    return [s[0] for s in STAGES]

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
    parser.add_argument("--stage", choices=get_stage_names(), help="Run only a specific stage")
    args = parser.parse_args()

    if args.stage:
        for name, script, user in STAGES:
            if name == args.stage:
                run_pyinfra(script, ssh_user=user, auto_approve=args.auto_approve)
                return

    if args.fresh:
        run_pyinfra("0-bootstrap.py", ssh_user="root", auto_approve=args.auto_approve)

    run_pyinfra("1-system.py", auto_approve=args.auto_approve)
    run_pyinfra("2-docker.py", auto_approve=args.auto_approve)
    run_pyinfra("3-caddy.py", auto_approve=args.auto_approve)

if __name__ == "__main__":
    main()
