from pathlib import Path
from pyinfra.operations import server, files

from utils.find_project_root import find_project_root

PROJECT_ROOT = find_project_root()

server.user(
    name="Create deploy user",
    user="deploy",
    password=None,
    create_home=True,
    home="/home/deploy",
    groups=["sudo"],
    _sudo=True,
)

files.put(
    name="Set secure sudoers file"
    src=f"{PROJECT_ROOT}/vps/sudoers",
    dest="/etc/sudoers",
    mode="0440",
    _sudo=True,
)

server.shell(
    name="Authorize root SSH keys for deploy user",
    commands=[
        "mkdir -p /home/deploy/.ssh",
        "cp /root/.ssh/authorized_keys /home/deploy/.ssh/authorized_keys",
        "chown -R deploy:deploy /home/deploy/.ssh",
        "chmod 700 /home/deploy/.ssh",
        "chmod 600 /home/deploy/.ssh/authorized_keys",
    ],
    _sudo=True,
)

files.line(
    name="Disable SSH password authentication",
    path="/etc/ssh/sshd_config",
    line="PasswordAuthentication no",
    replace="PasswordAuthentication no",
    _sudo=True,
)

files.line(
    name="Disable root login",
    path="/etc/ssh/sshd_config",
    line="PermitRootLogin no",
    replace="PermitRootLogin no",
    _sudo=True,
)

files.line(
    name="Disable challenge-response authentication",
    path="/etc/ssh/sshd_config",
    line="ChallengeResponseAuthentication no",
    replace="ChallengeResponseAuthentication no",
    _sudo=True,
)

files.line(
    name="Use only public key auth",
    path="/etc/ssh/sshd_config",
    line="AuthenticationMethods publickey",
    replace="AuthenticationMethods publickey",
    _sudo=True,
)

server.shell(
    name="Enable firewall with OpenSSH",
    commands=[
        "ufw allow OpenSSH",
        "ufw default deny incoming",
        "ufw default allow outgoing",
        "ufw --force enable",
    ],
    _sudo=True,
)

server.shell(
    name="Restart SSH to apply hardening",
    commands=["systemctl restart ssh"],
    _sudo=True,
)