# 2. Environment variables, secrets, logging and resource quotas

## 2.1 Configuration versus secrets

| Kind | Example | Where it lives | Why |
| --- | --- | --- | --- |
| Plain settings | table name, bucket name, port, region | Environment variables in `/etc/cloud-app.env` (loaded by systemd) | Differs per environment, not sensitive. Same code runs anywhere. |
| Secret | the admin key that protects delete | **SSM Parameter Store** `SecureString` at `/cloud-web-app/admin-key` | Encrypted at rest, access controlled by IAM, auditable |
| Credentials for AWS itself | none | Temporary credentials from the **instance role** | Nothing to leak, they rotate automatically |

Rules followed here:

1. No secret in Git. `.gitignore` blocks `.env`, `*.pem`, `*.tfstate` and `terraform.tfvars`.
2. No secret in `user_data`, since it can be read from the instance metadata and the console.
3. The env file holds only the **name** of the parameter, never its value.
4. The app reads the secret once at startup (`loadSecrets()` in `app/lib/config.js`) and keeps it in memory only.
5. The secret is never logged.

Read the secret on demand (it is not printed by Terraform):

```powershell
aws ssm get-parameter --name /cloud-web-app/admin-key --with-decryption --query Parameter.Value --output text
```

Trade-off to know: Terraform generates the value (`random_password`), so it is also stored in `terraform.tfstate`. That is why state is git-ignored. In a team setup, store state in an encrypted remote backend (S3 with encryption and locking) or create the parameter outside Terraform.

To rotate the key: update the parameter (`aws ssm put-parameter --overwrite ...`) and restart the service (`sudo systemctl restart cloud-app`).

## 2.2 Application logging

The app writes **structured JSON, one event per line**, so logs can be searched and filtered:

```json
{"time":"2026-11-15T10:12:03.511Z","level":"info","msg":"request","method":"POST","path":"/api/notes","status":201,"ms":12,"ip":"41.202.1.5"}
{"time":"2026-11-15T10:12:09.020Z","level":"warn","msg":"admin authentication failed","ip":"198.51.100.4"}
```

| Level | Used for |
| --- | --- |
| `info` | Requests, note created, upload, startup |
| `warn` | Failed admin authentication |
| `error` | Unhandled errors, startup failure |

Where the logs go:

1. **stdout** → systemd journal: `journalctl -u cloud-app -f`
2. **`/var/log/cloud-app/app.log`** → the CloudWatch agent ships it to log group `/cloud-web-app/app`, stream `<instance-id>-app`. nginx access logs go to the stream `<instance-id>-nginx`.
3. `logrotate` keeps three days on disk; CloudWatch keeps **7 days** (set in Terraform).

Useful CloudWatch Logs Insights query (CloudWatch, Logs Insights, select the log group):

```
fields @timestamp, msg, status, path, ms
| filter level = "warn" or status >= 500
| sort @timestamp desc
| limit 50
```

## 2.3 Resource quotas and limits

"Quota" here means limits that stop a mistake or an abuser from using unlimited resources or money.

| Layer | Limit | Where it is set |
| --- | --- | --- |
| Cost | Email at 80% of a $5 monthly budget | `aws_budgets_budget` in `main.tf` |
| Alerts | CPU above 80% for 10 minutes; failed status checks | `aws_cloudwatch_metric_alarm` |
| Process | `MemoryMax=300M`, `CPUQuota=80%`, `TasksMax=100` | systemd unit in `user_data.sh.tftpl` |
| Requests | 30 write requests per minute per IP | `express-rate-limit` in `app/server.js` |
| Uploads | 2 MB per file, one file per request, 6 allowed types; nginx caps the body at 3 MB | `app/server.js`, nginx config |
| Storage | Uploads deleted after 30 days; log group kept 7 days; logs rotated on disk | S3 lifecycle, log group, logrotate |
| Database | On-demand billing, nothing to over-provision; `Scan` capped at 100 items | `aws_dynamodb_table`, `app/lib/store.js` |
| Account | AWS **Service Quotas** cap how many instances, IPs and so on the account may use | see below |

Inspect the account-level quotas:

```powershell
# vCPUs allowed for running On-Demand Standard instances (t, m, c, r families)
aws service-quotas get-service-quota --service-code ec2 --quota-code L-1216C47A --region us-east-1

# All DynamoDB quotas
aws service-quotas list-service-quotas --service-code dynamodb --region us-east-1 --query "Quotas[].[QuotaName,Value]" --output table
```

Check **Billing, Free Tier** in the console as well. Free tier rules differ by account age, so confirm what your account includes.

## 2.4 Why these controls matter together

- A leaked repo exposes no secrets, because there are none in it.
- A compromised app can only touch one table, one bucket and one parameter.
- A traffic spike or abuse is slowed by rate limits and process caps, and you are emailed by the alarms.
- A forgotten server shows up as a budget alert instead of a surprise bill.
