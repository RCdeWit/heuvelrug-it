import os

from pyinfra.operations import server, files, systemd

from utils.find_project_root import find_project_root

PROJECT_ROOT = find_project_root()
if "TF_VAR_domain" not in os.environ:
    raise SystemExit("ERROR: TF_VAR_domain is not set. Set it in your .env file and run: source .env")
DOMAIN = os.environ["TF_VAR_domain"]
# Optional; empty means no apex site block is rendered. Shares the TF_VAR_
# prefix because Terraform reads the same value to decide on the apex A record.
APEX_REDIRECT_URL = os.environ.get("TF_VAR_apex_redirect_url", "")
# The stock release binary. Caddy obtains each site's certificate through the
# HTTP-01 challenge on port 80, so it needs no DNS module and no API token.
CADDY_VERSION = "v2.11.7"

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
    name=f"Download Caddy {CADDY_VERSION}",
    src=f"https://github.com/caddyserver/caddy/releases/download/{CADDY_VERSION}/caddy_{CADDY_VERSION.lstrip('v')}_linux_amd64.tar.gz",
    dest="/tmp/caddy.tar.gz",
    force=True,
    _sudo=True,
)

server.shell(
    name="Install Caddy",
    commands=[
        "tar -xzf /tmp/caddy.tar.gz -C /tmp caddy",
        "install -m 755 /tmp/caddy /usr/local/bin/caddy",
        "rm -f /tmp/caddy /tmp/caddy.tar.gz",
    ],
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
    apex_redirect_url=APEX_REDIRECT_URL,
)

server.shell(
    name="Reload systemd after changing the service file",
    commands=["systemctl daemon-reload"],
    _sudo=True,
)

systemd.service(
    name="Enable and start Caddy",
    _sudo=True,
    service="caddy",
    enabled=True,
    restarted=True,
    running=True,
)
