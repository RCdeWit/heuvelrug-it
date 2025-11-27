# GL/PvdA Heuvelrug IT

[![Deploy
Infra](https://github.com/RCdeWit/heuvelrug-it/actions/workflows/deploy.yml/badge.svg?branch=main)](https://github.com/RCdeWit/heuvelrug-it/actions/workflows/deploy.yml)

Repository containing the infrastructure-as-code (IaC) for GL/PvdA's IT stack. It
uses Terrafrom to provision cloud resources on Hetzner, and Pyinfra to configure
those resources. It runs services through Docker containers.

## How to deploy

The GitHub Actions workflow ensures that deployments happen automatically
whenever changes are merged into the `main` branch. You can also trigger a manual deployment with the `workflow_dispatch` trigger.

### Prerequisites

- S3 bucket for Terraform state
- Hetzner account
- Tailscale account and Tailnet

### Environment

The following environment variables should be configured as repository variables
in GitHub Actions:

```yaml
DOMAIN: rcdw.nl
SSH_KEY_DEPLOYMENT_PUBLIC: ssh-rsa AAA...
TF_S3_BUCKET: infra-tfstate
TF_S3_ENDPOINT: https://fly.storage.tigris.dev
TF_S3_REGION: auto
```

The following secrets are also required:

```yaml
GH_PAT
HCLOUD_API_TOKEN
SSH_KEY_DEPLOYMENT_PRIVATE
TF_S3_ACCESS_KEY
TF_S3_SECRET_KEY
```

For the `GH_PAT`, the personal access token should have read access to the private config repository.

## How to deploy manually

If required, you can also follow the deployment steps manually. The instructions
below mirror the steps in the GitHub Actions workflow and should work if you set
the environment variables as specified in `configs/.env.example`.

> [!NOTE]  
> The pipeline configures the VPS to only accept one SSH key. If you've
> previously deployed from another machine or GitHub Actions, it's probably
> easiest to `terraform destroy` and do a fresh deployment.

### 1. Create Terraform state and initialize

1. Create an S3 compatible bucket (e.g., using
   [Tigris](https://console.tigris.dev))
2. Create an access key and add the credentials to `terraform/backend.tfvars`
3. From the `terraform` directory, run `terraform init
-backend-config=backend.tfvars`

### 2. Provision resources

1. From the `terraform` directory, deploy with `terraform apply`

### 3. Configure VPS

This project uses PyInfra to manage the provisioned resources in an imperative
manner. `pyinfra/configure_vps.py` provides a wrapper script for the
different stages in the deployement.

1. For first-time deployments: `uv run pyinfra/configure_vps.py --fresh`.
   This executes the `0-bootstrap` script and creates a `deploy` user before running
   the subsequent steps.
3. For subsequent deployments: `uv run pyinfra/configure_vps.py`

### Update VPS

To update the VPS, for example to upgrade packages, simply run `uv run
scripts/deploy_reverse_proxy.py`. To use a new Ubuntu image, it's easiest to do
a fresh deployment.
