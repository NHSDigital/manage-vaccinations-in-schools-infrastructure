# Releasing

All infrastructure changes follow the same general process: changes are made on
a feature branch, reviewed via PR, merged to `main`, and then deployed using
GitHub Actions workflows (or manually for stacks without workflows).

Deployments are manual — there are no automatic deployments triggered by merging
to `main`. Each Terraform root module has its own state and can be deployed
independently.

For an overview of what each stack contains, see [stacks.md](stacks.md).

## Release tags

We use semantic versioning tags (e.g. `v1.3.0`) to mark releases. Create a tag
when deploying a set of changes to production:

```shell
git tag v1.4.0
git push origin v1.4.0
```

Use your judgement for version bumps:

- **Patch** (`v1.3.1`): backwards-compatible fixes, e.g. correcting a security
  group rule or adjusting a scaling parameter.
- **Minor** (`v1.4.0`): new resources or features that don't change existing
  behaviour, e.g. adding a new ECS service or a new monitoring alarm.
- **Major** (`v2.0.0`): breaking changes that require coordination, e.g.
  replacing the database engine, restructuring the VPC, or changes that require
  other teams to update their workflows.

Tags apply to the repository as a whole. If a release only touches one stack,
the tag still covers the full repo state at that point.

## General process

1. Create a branch with your Terraform changes.
1. Open a PR against `main`. The `lint.yml` and `test.yml` workflows will run
   automatically to validate formatting and `terraform validate` across all root
   modules.
1. Get the PR reviewed and merged.
1. Deploy to a non-production environment first (e.g. `qa` or `test`) using the
   appropriate workflow or manual process.
1. Verify the changes in the non-production environment.
1. Deploy to production. Production deployments require approval via GitHub
   environment protection rules and post a notification to the releases Slack
   channel.

## Stacks and deployment order

The stacks have dependencies that determine the order in which they should be
deployed. The dependency graph is:

```
bootstrap (one-time, local state)
  └── account
        ├── app
        ├── data_replication
        ├── backup
        ├── monitoring/aws
        │     └── monitoring/grafana
        └── assurance_testing
```

**`bootstrap`** must be run first to create the S3 state buckets. This is a
one-time operation and uses local state. This has already been done for all environments
and is not required for any normal day-to-day deployments.

**`account`** must be deployed before any other stack, as it creates the IAM
roles used by GitHub Actions workflows, ECR repositories, and shared S3 buckets.
If there are no changes in the account directory then this step can be skipped.

The remaining stacks (`app`, `data_replication`, `backup`, `monitoring`,
`assurance_testing`) can be deployed in any order after `account`, though
`monitoring/grafana` depends on `monitoring/aws`.

## Deploying each stack

### `app`

**Workflow:** [deploy-infrastructure.yml](../.github/workflows/deploy-infrastructure.yml)

1. Run the **Deploy Infrastructure** workflow from `main`.
1. Select the target environment.
1. Optionally specify a git ref to deploy (commit SHA or tag). If left blank,
   the workflow deploys from `main`. For production releases, use the release
   tag (e.g. `v1.4.0`) to ensure the deployed code matches the tagged release.
1. The workflow runs `terraform plan`, uploads the plan as an artifact, then
   waits for approval (production only) before applying.
1. For production, a Slack notification is posted and GitHub environment
   approval is required.

**Note:** ECS task definitions are managed by CodeDeploy, not Terraform.
Terraform ignores changes to `task_definition` on ECS services. See
[deployment-process.md](../documentation/deployment-process.md) and
[resource-modification-strategy.md](../documentation/resource-modification-strategy.md)
for details on blue-green deployments.

### `account`

**Workflow:** None. Manual deployment required. Requires being signed in with admin priviledges (see [terraform.md](terraform.md))
and settig the appropriate profile. Once you are signed into the aws cli you can execute

```shell
./scripts/apply_account_stack.sh <environment>
```

The script initialises Terraform with the correct backend, runs a plan for review, and applies after confirmation. For production it requires you to type
`production` to confirm.

**Important:** Changes to IAM roles can affect all other stacks' ability to
deploy. Coordinate carefully and deploy to non-prod first.

### `data_replication`

**Workflow:** [refresh-data-replication.yml](../.github/workflows/refresh-data-replication.yml)

1. Run the **Refresh Data Replication** workflow from `main`.
1. Select the target environment and optionally take a fresh DB snapshot.
1. The workflow retrieves the latest snapshot, plans, and applies.
1. For production with manual trigger, GitHub environment approval is required.

There is also a **scheduled** run
([scheduled-data-replication-refresh.yml](../.github/workflows/scheduled-data-replication-refresh.yml))
that refreshes the production data replica nightly at midnight UTC.

### `backup`

**Workflow:** [deploy-backup-infrastructure.yml](../.github/workflows/deploy-backup-infrastructure.yml)

1. Run the **Deploy Backup Infrastructure** workflow from `main`.
1. Select the target environment (development or production).
1. The workflow plans and applies. Production requires GitHub environment
   approval.

**Note:** This workflow requires the `BACKUP_MODULES_ACCESS_TOKEN` secret (a
fine-grained PAT) to fetch an external NHSDigital Terraform module.

### `monitoring/aws` and `monitoring/grafana`

**Workflow:** [deploy-monitoring.yml](../.github/workflows/deploy-monitoring.yml) (covers both)

1. Run the **Deploy Monitoring** workflow from `main`.
1. Select the target environment (development or production).
1. The workflow plans and applies the AWS monitoring stack, then applies the
   Grafana configuration if the AWS step succeeds.

The Grafana configuration can also be deployed independently using the
[Apply Grafana Configuration](../.github/workflows/apply-grafana-config.yml)
workflow.

### `assurance_testing`

**Workflow:** None. Manual deployment required.

```shell
cd assurance_testing
terraform init -backend-config="env/non-prod-backend.hcl" -upgrade -reconfigure
terraform plan -var-file="env/non-prod.tfvars" -out=tfplan
# Review the plan
terraform apply tfplan
```

## Concurrency

All deployment workflows use concurrency groups scoped to the environment (e.g.
`deploy-infrastructure-production`). This prevents parallel runs of the same
workflow targeting the same environment.
