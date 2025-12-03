import os

from io import StringIO

from pyinfra import host
from pyinfra.facts.server import Command
from pyinfra.operations import apt, server, files

from utils.find_project_root import find_project_root

PROJECT_ROOT = find_project_root()
POSTGRES_PASSWORD = os.environ["POSTGRES_PASSWORD"]
NEXTCLOUD_ADMIN_USER = os.environ.get("NEXTCLOUD_ADMIN_USER", "admin")
NEXTCLOUD_ADMIN_PASSWORD = os.environ["NEXTCLOUD_ADMIN_PASSWORD"]

MOUNT_POINT = host.get_fact(
    Command,
    "findmnt -n -o TARGET /dev/disk/by-id/scsi-0HC_Volume_* | grep -v '/var/lib/docker'"
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
# Deploy Nextcloud All-In-One (AIO)
#

server.shell(
    name="Create AIO directory",
    commands=["mkdir -p /opt/nextcloud-aio"],
    _sudo=True,
)

server.shell(
    name="Create Nextcloud directories on volume",
    commands=[
        f"mkdir -p {MOUNT_POINT}/nextcloud_aio_mastercontainer",
        f"mkdir -p {MOUNT_POINT}/ncdata",
        f"mkdir -p {MOUNT_POINT}/nextcloud_db",
        f"mkdir -p {MOUNT_POINT}/nextcloud_data"
    ],
    _sudo=True,
)

server.shell(
    name="Create Docker volume with bind mount to attached storage",
    commands=[
        f"docker volume inspect nextcloud_aio_mastercontainer >/dev/null 2>&1 || "
        f"docker volume create --driver local "
        f"--opt type=none "
        f"--opt o=bind "
        f"--opt device={MOUNT_POINT}/nextcloud_aio_mastercontainer "
        f"nextcloud_aio_mastercontainer"
    ],
    _sudo=True,
)

files.template(
    name="Upload docker-compose for AIO",
    src=f"{PROJECT_ROOT}/vps/docker/nextcloud.yml.j2",
    dest="/opt/nextcloud-aio/docker-compose.yml",
    mode="0644",
    mount_point=MOUNT_POINT,
    _sudo=True,
)

files.template(
    name="Create .env file with secrets",
    src=StringIO(
        f"POSTGRES_PASSWORD={POSTGRES_PASSWORD}\n"
        f"NEXTCLOUD_ADMIN_USER={NEXTCLOUD_ADMIN_USER}\n"
        f"NEXTCLOUD_ADMIN_PASSWORD={NEXTCLOUD_ADMIN_PASSWORD}\n"
    ),
    dest="/opt/nextcloud-aio/.env",
    mode="0600",
    _sudo=True,
)

server.shell(
    name="Launch Nextcloud AIO",
    commands=[
        "docker compose -f /opt/nextcloud-aio/docker-compose.yml up -d"
    ],
    _sudo=True,
)
