# MAVIS Infrastructure as Code

This repository contains Terraform configurations for provisioning and managing the infrastructure supporting the MAVIS application.

## Overview

The infrastructure is organized into several key components:

- **Account Management**: Base AWS account configuration including IAM, S3, and ECR
- **Application Infrastructure**: Core ECS services, RDS databases, networking, and monitoring
- **Data Replication**: DMS configurations and replication instance management
- **Backup Strategy**: Cross-account backup implementation using AWS Backup
- **Monitoring**: Grafana dashboards and CloudWatch alerting configurations
- **Assurance Testing**: Performance and end-to-end testing infrastructure

## Repository Structure

```
.
├── account/            # Account-level resources (IAM, S3, ECR)
├── app/                # Core application infrastructure (ECS, RDS, VPC)
├── data_replication/   # Database migration and replication resources
├── backup/             # Cross-account backup implementation
├── monitoring/         # Monitoring and alerting configurations
├── assurance_testing/  # Performance and end-to-end testing infrastructure
├── documentation/      # Architectural decisions and operational guides
└── modules/            # Reusable Terraform modules
```

## Documentation

- [Infrastructure Overview](documentation/infrastructure-overview.md)
- [Resource Modification Strategy](documentation/resource-modification-strategy.md)
- [Terraform Lifecycle Management](documentation/terraform-lifecycle-and-permissions.md)
