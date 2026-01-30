# Terraform manual

The Mavis infrastructure is managed with terraform. For a detailed overview over the
infrastructure see [infrastructure-overview.md](../documentation/infrastructure-overview.md).

## Setup

### AWS profile

To set up `awscli` for the first time:

```bash
aws configure sso
```

Your `~/.aws/config` should look something like:

```bash
[default]
region = eu-west-2
[profile Admin-ACCOUNT_ID]
sso_session = SESSION_NAME
sso_account_id = ACCOUNT_ID
sso_role_name = Admin
region = eu-west-2
[sso-session SESSION_NAME]
sso_start_url = https://SUBDOMAIN.awsapps.com/start#
sso_region = eu-west-2
sso_registration_scopes = sso:account:access
```

Before running `terraform ...` make sure you set the environment variable to the desired profile, e.g.

```bash
export AWS_PROFILE=default
```

### Creating a new environment

This repo contains the `bootstrap` folder stores the AWS resources required for remote state management of the app infrastructure.

#### Bootstrap -- Pre-requisites for creating a new environment:

_Case 1:_ Setting up the first environment in an account

To set up everything from scratch, run `./scripts/bootstrap.sh <ENV_NAME>` first in the `terraform/scripts` folder and follow
any instructions from the output.

_Case 2:_ Adding more environments to an account

To add more environments to an account, run `./scripts/bootstrap.sh <ENV_NAME> --environment-only` in the `terraform/scripts`
folder and follow any instructions from the output.

If this environment is not yet included in the allowed values of variable "environment"
in [variables.tf](../app/variables.tf) this must be updated.

### Configuring the terraform backend

We employ a multi-backend configuration (instead of workspaces) to adjust the configuration for multiple environments.
To work with a specific environment just run

```bash
terraform init -backend-config=env/<environment>-backend.hcl
```

in the `app` directory.
