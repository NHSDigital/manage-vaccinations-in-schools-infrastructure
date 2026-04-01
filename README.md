# Manage vaccinations in schools (Mavis) — Infrastructure

This repository contains Terraform configuration for provisioning and managing
the infrastructure supporting the Mavis application.

## Overview

The infrastructure is organized into several key components:

- **Account Management**: Base AWS account configuration including IAM, S3, and ECR
- **Application Infrastructure**: Core ECS services, RDS databases, networking, and monitoring
- **Data Replication**: Data replication for environments
- **Backup Strategy**: Cross-account backup implementation using AWS Backup
- **Monitoring**: Grafana dashboards alerting configurations
- **Assurance Testing**: Performance and end-to-end testing infrastructure

## Directory structure

```
.
├── account/            # Account-level resources (IAM, S3, ECR)
├── app/                # Core application infrastructure (ECS, RDS, VPC)
├── data_replication/   # Data replication configuration
├── backup/             # Cross-account backup implementation
├── monitoring/         # Monitoring and alerting configurations
├── assurance_testing/  # Performance and end-to-end testing infrastructure
├── documentation/      # Architectural decisions and operational guides
└── modules/            # Reusable Terraform modules
```

## Development

We use [`mise`](https://mise.jdx.dev/) and [`hk`](https://hk.jdx.dev/) to
manage dependencies and hooks.

```shell
$ mise install
$ hk fix --all
```

## Further documentation

- [Infrastructure Overview](documentation/infrastructure-overview.md)
- [Resource Modification Strategy](documentation/resource-modification-strategy.md)
- [Terraform Lifecycle Management](documentation/terraform-lifecycle-and-permissions.md)
