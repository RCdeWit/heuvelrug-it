import os

from io import StringIO

from pyinfra import host
from pyinfra.facts.server import Command
from pyinfra.operations import apt, server, files

from utils.find_project_root import find_project_root
from utils.get_terraform_output import get_terraform_output

PROJECT_ROOT = find_project_root()
POSTGRES_PASSWORD = os.environ["POSTGRES_PASSWORD"]
NEXTCLOUD_ADMIN_USER = os.environ.get("NEXTCLOUD_ADMIN_USER", "admin")
NEXTCLOUD_ADMIN_PASSWORD = os.environ["NEXTCLOUD_ADMIN_PASSWORD"]
REDIS_PASSWORD = os.environ["REDIS_PASSWORD"]
RESTIC_PASSWORD = os.environ["RESTIC_PASSWORD"]
AWS_ACCESS_KEY_ID = os.environ["TF_VAR_hetzner_s3_access_key"]
AWS_SECRET_ACCESS_KEY = os.environ["TF_VAR_hetzner_s3_secret_key"]
HETZNER_REGION = os.environ.get("TF_VAR_hetzner_region", "nbg1")
AWS_S3_ENDPOINT = f"https://{HETZNER_REGION}.your-objectstorage.com"
# Get bucket name dynamically from Terraform outputs
AWS_S3_BUCKET = get_terraform_output("s3_bucket")
BACKUP_RETENTION_DAYS = os.environ.get("BACKUP_RETENTION_DAYS", "30")
HEALTHCHECK_URL = os.environ.get("HEALTHCHECK_URL", "")

# Nextcloud Talk configuration
TURN_SECRET = os.environ.get("TURN_SECRET", "")
SIGNALING_SECRET = os.environ.get("SIGNALING_SECRET", "")
SIGNALING_HASHKEY = os.environ.get("SIGNALING_HASHKEY", "")
SIGNALING_BLOCKKEY = os.environ.get("SIGNALING_BLOCKKEY", "")
JANUS_ADMIN_SECRET = os.environ.get("JANUS_ADMIN_SECRET", "")
JANUS_TURN_PASSWORD = os.environ.get("JANUS_TURN_PASSWORD", "")

# SMTP configuration (using official Nextcloud Docker env var names)
SMTP_HOST = os.environ.get("SMTP_HOST", "smtp-relay.brevo.com")
SMTP_PORT = os.environ.get("SMTP_PORT", "587")
SMTP_SECURE = os.environ.get("SMTP_SECURE", "tls")
SMTP_AUTHTYPE = os.environ.get("SMTP_AUTHTYPE", "LOGIN")
SMTP_NAME = os.environ.get("SMTP_NAME", "")  # Username for SMTP auth
SMTP_PASSWORD = os.environ.get("SMTP_PASSWORD", "")
MAIL_FROM_ADDRESS = os.environ.get("MAIL_FROM_ADDRESS", "noreply")
# Reuse the domain from Terraform variables (no need for separate MAIL_DOMAIN)
DOMAIN = os.environ.get("TF_VAR_domain", "dobbertjeduik.nl")

# Komodo Periphery configuration
PERIPHERY_PASSKEY = os.environ.get("PERIPHERY_PASSKEY", "")

MOUNT_POINT = host.get_fact(
    Command,
    "findmnt -n -o TARGET /dev/disk/by-id/scsi-0HC_Volume_* | grep -v '/var/lib/docker'"
)

# Get Tailscale IP for Periphery binding (empty if Tailscale not running)
TAILSCALE_IP = host.get_fact(
    Command,
    "tailscale ip -4 2>/dev/null || echo ''"
)

apt.packages(
    name="Install dependencies for Docker and backup tools",
    packages=["ca-certificates", "curl", "gnupg", "restic"],
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

files.put(
    name="Configure Docker daemon (disable inherited DNS search domains)",
    # Prevents Tailscale's search domain from being injected into containers,
    # which would break inter-container DNS resolution (e.g. nextcloud -> nextcloud-db)
    src=StringIO('{"dns-search": ["."]}\n'),
    dest="/etc/docker/daemon.json",
    mode="0644",
    _sudo=True,
)

server.shell(
    name="Restart Docker daemon to apply config",
    commands=["systemctl restart docker"],
    _sudo=True,
)

#
# Deploy Nextcloud All-In-One (AIO)
#

server.shell(
    name="Create AIO directory",
    commands=["mkdir -p /opt/nextcloud"],
    _sudo=True,
)

server.shell(
    name="Create Nextcloud directories on volume",
    commands=[
        f"mkdir -p {MOUNT_POINT}/nextcloud_mastercontainer",
        f"mkdir -p {MOUNT_POINT}/ncdata",
        f"mkdir -p {MOUNT_POINT}/nextcloud_db",
        f"mkdir -p {MOUNT_POINT}/nextcloud_data",
        f"mkdir -p {MOUNT_POINT}/redis_data",
        f"mkdir -p {MOUNT_POINT}/clamav_data"
    ],
    _sudo=True,
)

server.shell(
    name="Create Komodo Periphery directory",
    commands=["mkdir -p /etc/komodo"],
    _sudo=True,
)

server.shell(
    name="Create Docker volume with bind mount to attached storage",
    commands=[
        f"docker volume inspect nextcloud_mastercontainer >/dev/null 2>&1 || "
        f"docker volume create --driver local "
        f"--opt type=none "
        f"--opt o=bind "
        f"--opt device={MOUNT_POINT}/nextcloud_mastercontainer "
        f"nextcloud_mastercontainer"
    ],
    _sudo=True,
)

files.template(
    name="Upload docker-compose file for Nextcloud",
    src=f"{PROJECT_ROOT}/vps/docker/nextcloud.yml.j2",
    dest="/opt/nextcloud/docker-compose.yml",
    mode="0644",
    mount_point=MOUNT_POINT,
    domain=DOMAIN,
    _sudo=True,
)

server.shell(
    name="Create Collabora fonts directory",
    commands=["mkdir -p /opt/nextcloud/collabora/fonts"],
    _sudo=True,
)

files.sync(
    name="Sync Collabora custom fonts",
    src=f"{PROJECT_ROOT}/vps/collabora/fonts/",
    dest="/opt/nextcloud/collabora/fonts/",
    _sudo=True,
)

server.shell(
    name="Create Nextcloud config directory",
    commands=["mkdir -p /opt/nextcloud/nextcloud"],
    _sudo=True,
)

files.template(
    name="Upload Nextcloud custom entrypoint script",
    src=f"{PROJECT_ROOT}/vps/nextcloud/nextcloud-entrypoint.sh",
    dest="/opt/nextcloud/nextcloud/nextcloud-entrypoint.sh",
    mode="0755",
    domain=DOMAIN,
    _sudo=True,
)

files.put(
    name="Upload Nextcloud backup script",
    src=f"{PROJECT_ROOT}/vps/nextcloud/backup.sh",
    dest="/opt/nextcloud/nextcloud/backup.sh",
    mode="0755",
    _sudo=True,
)

# Komodo Periphery - Allow port 8120 on Tailscale interface only
server.shell(
    name="Allow Komodo Periphery port through firewall (Tailscale only)",
    commands=[
        "ufw allow in on tailscale0 to any port 8120 proto tcp comment 'Komodo Periphery (Tailscale only)'",
    ],
    _sudo=True,
)

# Nextcloud Talk - Firewall rules for TURN/STUN
server.shell(
    name="Allow TURN/STUN ports through firewall",
    commands=[
        # STUN/TURN standard ports
        "ufw allow 3478/udp comment 'TURN/STUN UDP'",
        "ufw allow 3478/tcp comment 'TURN/STUN TCP'",
        # TURN relay port range (matching turnserver.conf min-port/max-port)
        # 100 ports is enough for ~50 concurrent calls
        "ufw allow 49152:49252/udp comment 'TURN relay range'",
    ],
    _sudo=True,
)

# Nextcloud Talk configuration files
server.shell(
    name="Create Talk config directory",
    commands=["mkdir -p /opt/nextcloud/talk"],
    _sudo=True,
)

files.template(
    name="Upload coturn (TURN server) configuration",
    src=f"{PROJECT_ROOT}/vps/docker/talk/turnserver.conf",
    dest="/opt/nextcloud/talk/turnserver.conf",
    mode="0644",
    domain=DOMAIN,
    turn_secret=TURN_SECRET,
    janus_turn_password=JANUS_TURN_PASSWORD,
    _sudo=True,
)

files.template(
    name="Upload signaling server configuration",
    src=f"{PROJECT_ROOT}/vps/docker/talk/signaling.conf",
    dest="/opt/nextcloud/talk/signaling.conf",
    mode="0644",
    domain=DOMAIN,
    signaling_secret=SIGNALING_SECRET,
    signaling_hashkey=SIGNALING_HASHKEY,
    signaling_blockkey=SIGNALING_BLOCKKEY,
    _sudo=True,
)

files.put(
    name="Upload NATS configuration",
    src=f"{PROJECT_ROOT}/vps/docker/talk/nats.conf",
    dest="/opt/nextcloud/talk/nats.conf",
    mode="0644",
    _sudo=True,
)

VPS_IP = get_terraform_output("vps_ip")

files.template(
    name="Upload Janus gateway configuration",
    src=f"{PROJECT_ROOT}/vps/docker/talk/janus.jcfg",
    dest="/opt/nextcloud/talk/janus.jcfg",
    mode="0644",
    domain=DOMAIN,
    vps_ip=VPS_IP,
    janus_admin_secret=JANUS_ADMIN_SECRET,
    janus_turn_password=JANUS_TURN_PASSWORD,
    _sudo=True,
)

files.put(
    name="Upload Janus WebSocket transport configuration",
    src=f"{PROJECT_ROOT}/vps/docker/talk/janus.transport.websockets.jcfg",
    dest="/opt/nextcloud/talk/janus.transport.websockets.jcfg",
    mode="0644",
    _sudo=True,
)

files.template(
    name="Create .env file with secrets",
    src=StringIO(
        f"POSTGRES_PASSWORD={POSTGRES_PASSWORD}\n"
        f"NEXTCLOUD_ADMIN_USER={NEXTCLOUD_ADMIN_USER}\n"
        f"NEXTCLOUD_ADMIN_PASSWORD={NEXTCLOUD_ADMIN_PASSWORD}\n"
        f"REDIS_PASSWORD={REDIS_PASSWORD}\n"
        f"RESTIC_PASSWORD={RESTIC_PASSWORD}\n"
        f"AWS_ACCESS_KEY_ID={AWS_ACCESS_KEY_ID}\n"
        f"AWS_SECRET_ACCESS_KEY={AWS_SECRET_ACCESS_KEY}\n"
        f"AWS_S3_ENDPOINT={AWS_S3_ENDPOINT}\n"
        f"AWS_S3_BUCKET={AWS_S3_BUCKET}\n"
        f"BACKUP_RETENTION_DAYS={BACKUP_RETENTION_DAYS}\n"
        f"HEALTHCHECK_URL={HEALTHCHECK_URL}\n"
        f"SMTP_HOST={SMTP_HOST}\n"
        f"SMTP_PORT={SMTP_PORT}\n"
        f"SMTP_SECURE={SMTP_SECURE}\n"
        f"SMTP_AUTHTYPE={SMTP_AUTHTYPE}\n"
        f"SMTP_NAME={SMTP_NAME}\n"
        f"SMTP_PASSWORD={SMTP_PASSWORD}\n"
        f"MAIL_FROM_ADDRESS={MAIL_FROM_ADDRESS}\n"
        f"MAIL_DOMAIN={DOMAIN}\n"
        f"TURN_SECRET={TURN_SECRET}\n"
        f"SIGNALING_SECRET={SIGNALING_SECRET}\n"
        f"PERIPHERY_PASSKEY={PERIPHERY_PASSKEY}\n"
        f"TAILSCALE_IP={TAILSCALE_IP}\n"
    ),
    dest="/opt/nextcloud/.env",
    mode="0600",
    _sudo=True,
)

server.shell(
    name="Launch Nextcloud",
    commands=[
        "docker compose -f /opt/nextcloud/docker-compose.yml up -d"
    ],
    _sudo=True,
)

server.shell(
    name="Restart Talk containers to apply config changes",
    commands=[
        "docker compose -f /opt/nextcloud/docker-compose.yml restart signaling janus coturn nats || true"
    ],
    _sudo=True,
)

server.shell(
    name="Wait for PostgreSQL to be ready",
    commands=[
        "for i in $(seq 1 30); do "
        "docker compose -f /opt/nextcloud/docker-compose.yml exec -T nextcloud-db pg_isready -U nextcloud && break || sleep 2; "
        "done"
    ],
    _sudo=True,
)

server.shell(
    name="Fix database object ownership (ensure nextcloud user owns all objects)",
    commands=[
        # nextcloud is the superuser (POSTGRES_USER=nextcloud in docker-compose)
        "docker compose -f /opt/nextcloud/docker-compose.yml exec -T nextcloud-db "
        "psql -U nextcloud -d nextcloud -c "
        "\"DO \\$\\$ "
        "DECLARE r RECORD; "
        "BEGIN "
        "FOR r IN SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tableowner != 'nextcloud' LOOP "
        "EXECUTE 'ALTER TABLE ' || quote_ident(r.tablename) || ' OWNER TO nextcloud'; "
        "END LOOP; "
        "FOR r IN SELECT sequence_name FROM information_schema.sequences WHERE sequence_schema = 'public' LOOP "
        "EXECUTE 'ALTER SEQUENCE ' || quote_ident(r.sequence_name) || ' OWNER TO nextcloud'; "
        "END LOOP; "
        "END \\$\\$;\""
    ],
    _sudo=True,
)

server.shell(
    name="Wait for Nextcloud to be ready",
    commands=[
        # Wait for Nextcloud container to be running and config.php to exist
        "for i in $(seq 1 60); do "
        "docker compose -f /opt/nextcloud/docker-compose.yml exec -T nextcloud test -f /var/www/html/config/config.php && break || sleep 5; "
        "done"
    ],
    _sudo=True,
)

server.shell(
    name="Fix Nextcloud config to use nextcloud database user",
    commands=[
        # Nextcloud creates oc_admin* users on init, but we want to use the nextcloud superuser
        # This ensures consistency with the ownership fix and prevents permission issues
        "docker compose -f /opt/nextcloud/docker-compose.yml exec -T nextcloud "
        f"sed -i \"s/'dbuser' => 'oc_admin[^']*'/'dbuser' => 'nextcloud'/\" /var/www/html/config/config.php",
        "docker compose -f /opt/nextcloud/docker-compose.yml exec -T nextcloud "
        f"sed -i \"s/'dbpassword' => '[^']*'/'dbpassword' => '{POSTGRES_PASSWORD}'/\" /var/www/html/config/config.php"
    ],
    _sudo=True,
)

server.shell(
    name="Run Nextcloud upgrade if needed",
    commands=[
        # Run upgrade if needed (handles maintenance mode automatically)
        "docker compose -f /opt/nextcloud/docker-compose.yml exec -T -u www-data nextcloud "
        "php occ upgrade --no-interaction || true",
        # Disable maintenance mode if it's still on
        "docker compose -f /opt/nextcloud/docker-compose.yml exec -T -u www-data nextcloud "
        "php occ maintenance:mode --off || true"
    ],
    _sudo=True,
)
