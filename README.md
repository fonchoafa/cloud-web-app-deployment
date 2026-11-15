# Cloud Services & Web App Deployment (Module 3)

Codomax Digital Solutions internship, Module 3 (Day 11 to Day 15).
Author: Foncho Afanwi Ngwa ([@fonchoafa](https://github.com/fonchoafa))

This repository deploys a small Node.js web app, **Cloud Notes**, to AWS and documents the cloud services behind it: compute, object storage, a managed database, virtual networking, IAM and monitoring. Everything is created with Terraform and removed with one command.

**Live website:** `http://<fill in after deploy>`

## Architecture

```
Browser --HTTP 80--> Security group --> EC2 (Ubuntu 24.04) --> nginx --> Node.js app :3000
                                              |                                |
                                       IAM role (no keys)          +-----------+-----------+
                                              |                    v                       v
                                  CloudWatch logs + metrics   DynamoDB (notes)      S3 (attachments)
                                                              SSM Parameter Store (admin key)
```

| Layer | Service | Purpose |
| --- | --- | --- |
| Compute | EC2 `t3.micro`, systemd, nginx | Runs the app, limited to 300 MB RAM and 80% CPU |
| Object storage | S3 | Private, encrypted bucket for uploads, 30-day expiry |
| Managed database | DynamoDB (on-demand) | Stores notes |
| Networking | VPC, security group, `ufw` | 80 public, 22 only from my IP, app port not exposed |
| IAM | Instance role | Only the one table, bucket and parameter, no access keys on the server |
| Secrets | SSM Parameter Store (SecureString) | Admin key protecting `DELETE` |
| Monitoring | CloudWatch Logs, metrics, alarms, Budgets | JSON app logs, CPU and status alarms, cost alert by email |

## What is in this repo

| Path | Content |
| --- | --- |
| [app/](app/) | Express app, static front end, 7 automated tests (`npm test`) |
| [terraform/](terraform/) | `main.tf`, `variables.tf`, `outputs.tf`, `user_data.sh.tftpl` |
| [docs/01-cloud-services-exploration.md](docs/01-cloud-services-exploration.md) | Compute, storage, databases, networking, IAM and monitoring explained and explored |
| [docs/02-secrets-config-logging-quotas.md](docs/02-secrets-config-logging-quotas.md) | Environment variables, secrets, application logging and resource quotas |
| [docs/03-deployment-guide.md](docs/03-deployment-guide.md) | Step by step deployment, verification, troubleshooting and clean up |
| [scripts/](scripts/) | `smoke-test.ps1` checks a deployed site |
| [screenshots/](screenshots/) | Evidence from the live deployment (see checklist) |

## Quick start

```powershell
cd terraform
copy terraform.tfvars.example terraform.tfvars   # set my_ip_cidr and alert_email
terraform init
terraform plan
terraform apply
terraform output site_url
```

Push this repo to GitHub **before** `apply`, because the server clones the code from it. Full steps: [docs/03-deployment-guide.md](docs/03-deployment-guide.md).

## Objectives covered

- [x] Explore compute services, object storage, managed databases, virtual networking, IAM policies and cloud monitoring
- [x] Manage environment variables, secrets, application logging and resource quotas securely
- [x] Deploy a web application: application code, cloud compute, database and storage, networking, live web application

## Security notes

- No secrets in Git. `.env`, key files, `terraform.tfvars` and state files are git-ignored.
- The server has no stored AWS keys; it uses an IAM role with least privilege.
- The admin key lives in SSM Parameter Store and is read once at startup, never logged.
- IMDSv2 is required, the disk and bucket are encrypted, and the bucket blocks public access.
- SSH is key-only and open only to my own IP.

## Lessons learned

> Replace this with 3 or 4 sentences in your own words after you deploy: what went wrong at first, how you found the cause, and what you would do differently.

## Clean up

Run `terraform destroy` when the module has been reviewed so AWS does not keep billing for the server.
