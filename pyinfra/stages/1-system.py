import os
from pathlib import Path

from pyinfra import host
from pyinfra.facts.server import LinuxDistribution
from pyinfra.operations import apt, files, server

from utils.find_project_root import find_project_root

PROJECT_ROOT = find_project_root()

# Tailscale configuration
TAILSCALE_AUTH_KEY = os.environ.get("TAILSCALE_AUTH_KEY", "")

# Get Linux distribution info for Tailscale repo
linux_distribution = host.get_fact(LinuxDistribution)
linux_name = linux_distribution["release_meta"]["ID"]
linux_codename = linux_distribution["release_meta"]["VERSION_CODENAME"]

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

# ============================================================================
# Fail2ban - Brute force protection
# ============================================================================

apt.packages(
    name="Install fail2ban",
    packages=["fail2ban"],
    _sudo=True,
)

server.shell(
    name="Enable and start fail2ban",
    commands=[
        "systemctl enable fail2ban",
        "systemctl start fail2ban",
    ],
    _sudo=True,
)

# ============================================================================
# Kernel Hardening - Sysctl settings
# ============================================================================

files.put(
    name="Deploy kernel hardening sysctl config",
    src=f"{PROJECT_ROOT}/vps/99-hardening.conf",
    dest="/etc/sysctl.d/99-hardening.conf",
    mode="0644",
    _sudo=True,
)

server.shell(
    name="Apply sysctl hardening settings",
    commands=["sysctl --system"],
    _sudo=True,
)

# ============================================================================
# Tailscale - Mesh VPN for private networking
# ============================================================================

apt.key(
    name="Add Tailscale apt GPG key",
    src=f"https://pkgs.tailscale.com/stable/{linux_name}/{linux_codename}.noarmor.gpg",
    _sudo=True,
)

apt.repo(
    name="Add Tailscale apt repository",
    src=f"deb https://pkgs.tailscale.com/stable/{linux_name} {linux_codename} main",
    filename="tailscale",
    _sudo=True,
)

apt.packages(
    name="Install Tailscale",
    packages=["tailscale"],
    update=True,
    latest=True,
    _sudo=True,
)

if TAILSCALE_AUTH_KEY:
    server.shell(
        name="Join Tailnet with auth key",
        commands=[
            f"tailscale up --authkey={TAILSCALE_AUTH_KEY} --advertise-tags=tag:vps-external"
        ],
        _sudo=True,
    )
else:
    server.shell(
        name="Check Tailscale status (manual auth required if not connected)",
        commands=["tailscale status || echo 'Run: sudo tailscale up' to authenticate"],
        _sudo=True,
    )
