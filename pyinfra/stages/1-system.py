from pathlib import Path
from pyinfra.operations import apt, files

from utils.find_project_root import find_project_root

PROJECT_ROOT = find_project_root()

apt.update(
    name="Update apt package lists",
    _sudo=True,
)

apt.upgrade(
    name="Apply pending security updates",
    _sudo=True,
)

apt.packages(
    name="Install unattended-upgrades",
    packages=["unattended-upgrades", "apt-listchanges"],
    _sudo=True,
)

files.template(
    name="Configure automatic security updates",
    src=f"{PROJECT_ROOT}/vps/50unattended-upgrades.j2",
    dest="/etc/apt/apt.conf.d/50unattended-upgrades",
    _sudo=True,
)

files.template(
    name="Enable automatic updates",
    src=f"{PROJECT_ROOT}/vps/20auto-upgrades.j2",
    dest="/etc/apt/apt.conf.d/20auto-upgrades",
    _sudo=True,
)
