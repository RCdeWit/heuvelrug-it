import os
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from utils.get_terraform_output import get_terraform_output

ssh_user = os.getenv("SSH_USER", "deploy")
ssh_allow_agent = True

reverse_proxy = [
    (get_terraform_output("reverse_proxy_droplet_ip"), {"ssh_user": ssh_user, "ssh_allow_agent": ssh_allow_agent})
]