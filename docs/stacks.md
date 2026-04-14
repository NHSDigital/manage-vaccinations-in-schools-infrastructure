# Stack Overview

Each top-level directory in this repository is an independent Terraform root
module with its own state. This document provides a brief overview of what each
stack contains and why resources are grouped together.

For how to deploy each stack, see [releasing.md](releasing.md).

## `account` — Account-level resources

Resources that exist once per AWS account rather than once per environment: IAM
roles for GitHub Actions workflows, ECR repositories, S3 access log buckets, and
IAM Access Analyzer. All other stacks depend on `account` — it provides the IAM
roles that GitHub Actions workflows use to deploy, and the ECR repositories that
application images are pushed to. It must be deployed before any other stack.

These are separated because they are shared across all environments within an
account and change infrequently.

Environments: development (covers all non-production environments), production.

## `app` — Core application infrastructure

The main stack that most changes touch. It contains everything needed to run the
MAVIS application in a single environment: VPC, ECS Fargate services (web and
reporting), RDS Aurora Serverless database, ALB with blue/green target groups,
WAF, and Valkey (ElastiCache) for Sidekiq job queuing.

These resources are grouped together because they form a tightly coupled unit —
the application cannot function without networking, compute, database, and load
balancing all being in place.

Environments: qa, test, preview, training, sandbox-alpha, sandbox-beta,
performance, pentest, production.

## `data_replication` — Database replicas for migration testing

Creates isolated database replicas from production snapshots, along with a
dedicated ECS service for accessing the replica and network configuration with
optional egress CIDR filtering.

This is a separate stack because replicas are ephemeral — they are created,
tested against, and torn down independently of the main application
infrastructure.

Environments: qa, test, training, sandbox-alpha, sandbox-beta, production.

## `backup` — Cross-account backup

Configures AWS Backup for the RDS Aurora database, including cross-account vault
replication. Contains backup plans (7am and 7pm daily, 30-day retention), KMS
keys for SNS notifications, and S3 buckets for compliance reports.

Separated because backup configuration has its own lifecycle and uses an
external NHSDigital Terraform module.

Environments: development, production.

## `monitoring/aws` — CloudWatch and SNS

AWS-native monitoring resources: CloudWatch alarms, SNS topics, IAM workspace
configuration, and S3 storage for monitoring artifacts.

## `monitoring/grafana` — Grafana dashboards and alerts

Grafana provider configuration, dashboard definitions, and alert rules with
Slack webhook integration. Depends on `monitoring/aws` being deployed first.

Both monitoring stacks are separated from the main `app` stack because
monitoring changes independently and spans all environments rather than being
per-environment.

Environments: development, production.

## `assurance_testing` — Performance and E2E test infrastructure

ECR repositories for performance test and development images, with lifecycle
policies and an S3 bucket for test reports.

Separated because these resources support testing workflows rather than the
application itself, and they don't vary by environment.

## `bootstrap` — Terraform state buckets

One-time setup that creates the S3 buckets storing Terraform state for all other
modules. Uses local state (since it creates the remote backends). This has
already been run for all environments and is not needed for day-to-day work.
