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

MOUNT_POINT = host.get_fact(
    Command,
    "findmnt -n -o TARGET /dev/disk/by-id/scsi-0HC_Volume_* | grep -v '/var/lib/docker'"
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
        f"mkdir -p {MOUNT_POINT}/redis_data"
    ],
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
