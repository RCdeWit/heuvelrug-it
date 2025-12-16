import os

from io import StringIO

from pyinfra.operations import server, files, systemd

from utils.find_project_root import find_project_root

PROJECT_ROOT = find_project_root()
HETZNER_API_TOKEN = os.environ["TF_VAR_hcloud_token"]
DOMAIN = os.environ.get("TF_VAR_domain", "dobbertjeduik.nl")
GO_VERSION = os.environ.get("GO_VERSION", "1.23.4")

server.shell(
    name="Allow HTTP and HTTPS through Firewall",
    commands=[
        "ufw allow proto tcp from any to any port 80,443",
        "ufw --force enable"
    ],
    _sudo=True,
)

server.shell(
    name="Verify firewall allows HTTP/HTTPS",
    commands=["ufw status | grep -E '80|443'"],
    _sudo=True,
)

files.download(
    name="Download xcaddy",
    src="https://github.com/caddyserver/xcaddy/releases/download/v0.4.5/xcaddy_0.4.5_linux_amd64.tar.gz",
    dest="/tmp/xcaddy.tar.gz",
    _sudo=True,
)

server.shell(
    name="Extract and install xcaddy",
    commands=[
        "tar -xzf /tmp/xcaddy.tar.gz -C /tmp",
        "mv /tmp/xcaddy /usr/local/bin/xcaddy",
        "chmod +x /usr/local/bin/xcaddy",
    ],
    _sudo=True,
)

server.shell(
    name="Install Go",
    commands=[
        f"wget https://go.dev/dl/go{GO_VERSION}.linux-amd64.tar.gz -O /tmp/go.tar.gz",
        "rm -rf /usr/local/go",
        "tar -C /usr/local -xzf /tmp/go.tar.gz",
        "ln -sf /usr/local/go/bin/go /usr/bin/go",
    ],
    _sudo=True,
)

server.shell(
    name="Build Caddy with Hetzner DNS v2",
    commands=["xcaddy build --with github.com/caddy-dns/hetzner/v2@v2.0.0-preview-1 --output /usr/local/bin/caddy"],
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

files.template(
    name="Copy Caddy configuration to VPS",
    _sudo=True,
    src=f"{PROJECT_ROOT}/vps/caddy/Caddyfile",
    dest="/etc/caddy/Caddyfile",
    assume_exists=True,
    user="deploy",
    domain=DOMAIN,
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
