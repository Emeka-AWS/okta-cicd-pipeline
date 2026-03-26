# CI/CD Pipeline — Okta & AWS Infrastructure Management

## Overview

This repository contains a complete CI/CD pipeline design for managing an **Okta instance** and an **AWS server set** (EC2 or ECS/EKS). The pipeline automates provisioning, configuration, and lifecycle management of identity and compute infrastructure using GitHub Actions and Terraform.

---

## Architecture Summary

```
GitHub Actions (CI/CD Engine)
        │
        ├── Okta Management
        │     ├── User/Group provisioning (Terraform Okta provider)
        │     ├── Application assignments
        │     └── Policy enforcement
        │
        └── AWS Infrastructure
              ├── EC2 (traditional VM workloads)
              └── ECS/EKS (containerised workloads)
```

### Design Decisions

| Decision | Choice | Reason |
|---|---|---|
| IaC tool | Terraform | Native Okta + AWS providers, strong state management |
| Secrets management | AWS Secrets Manager + GitHub OIDC | No long-lived credentials in CI |
| Environments | dev → staging → prod | Progressive delivery, manual gate before prod |
| Container platform | ECS (default) / EKS (optional) | ECS simpler ops; EKS flag for Kubernetes teams |

---

## Repository Structure

```
.
├── .github/
│   └── workflows/
│       ├── okta-deploy.yml         # Okta provisioning pipeline
│       ├── aws-deploy.yml          # AWS infra pipeline (EC2 or ECS/EKS)
│       └── destroy.yml             # Teardown workflow (manual trigger)
├── terraform/
│   ├── modules/
│   │   ├── okta/                   # Okta Terraform module
│   │   ├── ec2/                    # EC2 module
│   │   └── ecs-eks/                # ECS/EKS module
│   └── environments/
│       ├── dev/
│       ├── staging/
│       └── prod/
├── scripts/
│   ├── validate.sh                 # Pre-flight checks
│   └── rotate-secrets.sh          # Secret rotation helper
├── docs/
│   └── architecture.md            # Extended architecture notes
└── README.md
```

---

## Pipeline Flow

### Okta Pipeline (`okta-deploy.yml`)

```
PR opened → terraform fmt/validate → terraform plan (posted as PR comment)
         → PR approved → terraform apply (dev) → smoke test
         → manual approval → terraform apply (prod)
```

### AWS Pipeline (`aws-deploy.yml`)

```
PR opened → lint + security scan (tfsec/checkov) → terraform plan
         → PR approved → apply (dev) → integration tests
         → manual approval gate → apply (staging) → apply (prod)
```

---

## Quick Start

### 1. Prerequisites

```bash
# Tools needed locally
terraform >= 1.5
aws-cli >= 2.0
okta-cli (optional, for local testing)
```

### 2. Configure GitHub Secrets

| Secret | Description |
|---|---|
| `OKTA_API_TOKEN` | Okta org-level API token |
| `OKTA_ORG_URL` | e.g. `https://yourorg.okta.com` |
| `AWS_ROLE_ARN` | IAM role assumed via OIDC (no static keys) |
| `TF_STATE_BUCKET` | S3 bucket for Terraform remote state |
| `TF_STATE_LOCK_TABLE` | DynamoDB table for state locking |

### 3. Bootstrap Terraform Backend

```bash
cd terraform/environments/dev
terraform init \
  -backend-config="bucket=$TF_STATE_BUCKET" \
  -backend-config="key=dev/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="dynamodb_table=$TF_STATE_LOCK_TABLE"
```

### 4. Run the Pipeline

Push a branch → open a PR → CI runs plan automatically → merge to trigger apply.

---

## Security Highlights

- **No static AWS credentials** — GitHub Actions uses OIDC to assume a scoped IAM role
- **Okta token stored in GitHub Secrets**, never in code
- **Terraform state encrypted** at rest in S3 with versioning enabled
- **tfsec + checkov** run on every PR to catch misconfigurations before apply
- **Manual approval gate** before every production deployment

---

## Extending This Design

- **Add Slack notifications**: integrate `slackapi/slack-github-action` into workflow steps
- **Add drift detection**: schedule `terraform plan` nightly and alert on unexpected changes
- **Switch EC2 → EKS**: set `var.compute_type = "eks"` in the environment tfvars
- **SAML/SSO integration**: extend the Okta module with `okta_app_saml` resources

---

## Author

Emeka — Systems Engineer Candidate
