#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default terraform directory
TERRAFORM_DIR="${TERRAFORM_DIR:-infrastructure/account-stack}"

# Function to print error and exit
error_exit() {
    echo -e "${RED}Error: $1${NC}" >&2
    exit 1
}

# Function to print info
info() {
    echo -e "${GREEN}$1${NC}"
}

# Function to print warning
warn() {
    echo -e "${YELLOW}$1${NC}"
}

# Function to print help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS] <account>

Apply Terraform account stack changes for the specified account.

ARGUMENTS:
  account    Target account: 'development' or 'production'

OPTIONS:
  -h, --help     Show this help message and exit

DESCRIPTION:
  This script initializes Terraform with the appropriate backend configuration,
  runs a plan, and applies changes to the specified account. For production
  account, confirmation is required before proceeding.

EXAMPLES:
  $0 development
  $0 production
  $0 --help

EOF
}

# Check for help flag
if [ $# -gt 0 ] && [[ "$1" =~ ^(-h|--help)$ ]]; then
    show_help
    exit 0
fi

# Check if environment argument is provided
if [ $# -lt 1 ]; then
    show_help
    exit 0
fi

ENVIRONMENT="$1"

if [[ ! "$ENVIRONMENT" =~ ^(development|production)$ ]]; then
    error_exit "Invalid environment: $ENVIRONMENT\nEnvironment must be 'development' or 'production'"
fi

# Safety check for production environment
if [ "$ENVIRONMENT" = "production" ]; then
    warn "WARNING: You are about to apply changes to the PRODUCTION environment!"
    echo -n "Type 'production' to confirm: "
    read -r CONFIRMATION
    if [ "$CONFIRMATION" != "production" ]; then
        error_exit "Production confirmation failed. Aborting."
    fi
    info "Production environment confirmed."
fi

info "Working with environment: $ENVIRONMENT"


# Initialize terraform with the appropriate backend
BACKEND_FILE="env/${ENVIRONMENT}-backend.hcl"

if [ ! -f "account/$BACKEND_FILE" ]; then
    error_exit "Backend file not found: account/$BACKEND_FILE"
fi

info "Initializing terraform with backend: $BACKEND_FILE"
terraform -chdir="account" init -reconfigure -upgrade -backend-config="$BACKEND_FILE" \
    || error_exit "Terraform init failed"

info "Running terraform plan..."


PLAN_FILE=$(mktemp)
trap "rm -f $PLAN_FILE" EXIT

# Run terraform plan and save to file
terraform -chdir="account" plan -var-file="env/${ENVIRONMENT}.tfvars" -out="$PLAN_FILE" \
    || error_exit "Terraform plan failed"

info "Terraform plan completed successfully"

# Show the plan
echo ""
warn "Review the terraform plan above"
echo ""
echo -n "Do you want to apply these changes? (yes/no): "
read -r APPLY_CONFIRMATION

if [ "$APPLY_CONFIRMATION" != "yes" ]; then
    warn "Terraform apply cancelled."
    exit 0
fi

info "Applying terraform changes..."
terraform -chdir="account" apply "$PLAN_FILE" || error_exit "Terraform apply failed"

info "Terraform apply completed successfully!"
