import os

from io import StringIO
from pyinfra.operations import apt, server, files, systemd
from utils.find_project_root import find_project_root

PROJECT_ROOT = find_project_root()
CADDY_URL = "https://caddyserver.com/api/download?os=linux&arch=amd64&p=github.com%2Fcaddy-dns%2Fhetzner"
HETZNER_API_TOKEN = os.environ["TF_VAR_hcloud_token"]

server.shell(
    name="Allow HTTP and HTTPS through Firewall",
    commands=["ufw allow proto tcp from any to any port 80,443", "ufw --force enable"],
    _sudo=True,
)

apt.packages(
    name="Install dependencies for Docker",
    packages=["ca-certificates", "curl", "gnupg"],
    update=True,
    _sudo=True,
)

server.shell(
    name="Install Docker from official script",
    commands=[
        "curl -fsSL https://get.docker.com | sh"
    ],
    _sudo=True,
)

apt.packages(
    name="Install Docker Compose Plugin",
    packages=["docker-compose-plugin"],
    _sudo=True,
)

#
# 2. Deploy Nextcloud All-In-One (AIO)
#

server.shell(
    name="Create AIO directory",
    commands=["mkdir -p /opt/nextcloud-aio"],
    _sudo=True,
)

files.put(
    name="Upload docker-compose for AIO",
    src=f"{PROJECT_ROOT}/vps/docker/nextcloud-aio.yml",
    dest="/opt/nextcloud-aio/docker-compose.yml",
    mode="0644",
    _sudo=True,
)

server.shell(
    name="Launch Nextcloud AIO",
    commands=[
        "docker compose -f /opt/nextcloud-aio/docker-compose.yml up -d"
    ],
    _sudo=True,
)

#
# 3. Install Caddy
#

files.download(
    name="Download custom Caddy binary with Hetzner DNS plugin",
    src=CADDY_URL,
    dest="/usr/local/bin/caddy",
    mode="755",
    _sudo=True,
)

server.user(
    name="Create Caddy system user",
    user="caddy",
    system=True,
    home="/var/lib/caddy",
    shell="/usr/sbin/nologin",
    _sudo=True,
)

server.shell(
    name="Create Caddy directories",
    commands=[
        "mkdir -p /etc/caddy /var/lib/caddy /var/log/caddy",
        "chown -R caddy:caddy /etc/caddy /var/lib/caddy /var/log/caddy",
    ],
    _sudo=True,
)

files.put(
    name="Install Caddy systemd service file",
    src=f"{PROJECT_ROOT}/vps/systemd/caddy.service",
    dest="/etc/systemd/system/caddy.service",
    _sudo=True,
)

files.put(
    name="Copy Caddy configuration to VPS",
    _sudo=True,
    src=f"{PROJECT_ROOT}/vps/caddy/Caddyfile",
    dest="/etc/caddy/Caddyfile",
    assume_exists=True,
    user="deploy",
)

server.shell(
    name="Create systemd drop-in directory",
    commands=["mkdir -p /etc/systemd/system/caddy.service.d"],
    _sudo=True,
)

files.template(
    name="Systemd drop-in with direct environment and Go DNS override",
    src=StringIO(
        f"[Service]\n"
        f"Environment=HETZNER_API_TOKEN={HETZNER_API_TOKEN}\n"
        f"Environment=GODEBUG=netdns=go\n"
    ),
    dest="/etc/systemd/system/caddy.service.d/env.conf",
    _sudo=True,
)

server.shell(
    name="Reload systemd after adding service drop-ins",
    commands=["systemctl daemon-reload"],
    _sudo=True,
)

systemd.service(
    name="Enable and start custom Caddy service",
    _sudo=True,
    service="caddy",
    enabled=True,
    restarted=True,
    running=True,
)