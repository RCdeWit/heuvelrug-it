import os
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))

from utils.get_terraform_output import get_terraform_output

ssh_user = os.getenv("SSH_USER", "deploy")
ssh_allow_agent = True

# SSH via Tailscale (public SSH is blocked by Hetzner firewall)
# Priority: env override > Terraform tailnet_hostname > public IP fallback
vps_host = (
    os.getenv("VPS_TAILNET_HOSTNAME")
    or get_terraform_output("tailnet_hostname")
    or get_terraform_output("vps_ip")
)

vps = [
    (vps_host, {"ssh_user": ssh_user, "ssh_allow_agent": ssh_allow_agent})
]