# 3. Deploying the web app on AWS

Flow: **Application Code → Cloud Compute → Database/Storage → Networking → Live Web Application**

```
 GitHub repo (app code)
        |  git clone (first boot)
        v
 EC2 t3.micro ── systemd ── Node.js app :3000
   ^   |  IAM role (no keys)         |            |
   |   |                             v            v
   |   |                       DynamoDB table   S3 bucket   (+ SSM secret, CloudWatch logs)
   |   v
 nginx :80  ◄── Security group (80 public, 22 my IP) ◄── Browser
```

## Before you start

1. AWS CLI logged in: `aws sts get-caller-identity`
2. Terraform installed: `terraform version`
3. SSH key at `~/.ssh/id_ed25519.pub` (created in Module 2)
4. Your public IP: `curl.exe -s ifconfig.me`
5. An email address you can open (alarms and budget alerts go there)

## Stage 1: Application code

The app is in `app/` (Node.js, Express). Run it locally first. With no AWS settings it keeps notes in memory and uploads in `./uploads`:

```powershell
cd app
npm install
npm test            # 7 tests should pass
copy .env.example .env
npm run dev         # open http://localhost:3000
```

Then **push the repo to GitHub before deploying**, because the server clones its code from the repo on first boot:

```powershell
cd ..
git init
git add .
git status          # no .tfstate, .tfvars, .env, node_modules or key files
git commit -m "Module 3: cloud web app deployment"
git branch -M main
git remote add origin https://github.com/fonchoafa/cloud-web-app-deployment.git
git push -u origin main
```

The repository must be **public** so the server can clone it without credentials.

## Stage 2: Cloud compute, database, storage and networking (Terraform)

```powershell
cd terraform
copy terraform.tfvars.example terraform.tfvars
code terraform.tfvars        # set my_ip_cidr (your IP + /32) and alert_email
terraform init
terraform validate
terraform plan               # expect: 20 to add
terraform apply              # type yes
```

Terraform creates, in order of dependency:

| Layer | Resources |
| --- | --- |
| Networking | Security group (80 public, 22 from your IP) in the default VPC |
| Storage | S3 bucket (private, encrypted, 30-day expiry) |
| Database | DynamoDB table (on-demand) |
| Secret | Random admin key in SSM Parameter Store (SecureString) |
| IAM | Role with least-privilege policy, CloudWatch agent policy, instance profile |
| Monitoring | Log group (7 days), SNS topic, two alarms, monthly budget |
| Compute | EC2 instance (Ubuntu 24.04, IMDSv2 only, encrypted disk) with a boot script |

The boot script (`user_data.sh.tftpl`) installs Node.js, clones the repo, installs dependencies, writes the env file, starts the systemd service, configures nginx and `ufw`, installs the CloudWatch agent and hardens SSH.

**Confirm the SNS email.** Open the "AWS Notification - Subscription Confirmation" email and click **Confirm subscription**, otherwise no alarm emails are sent.

## Stage 3: Live web application

Allow about **4 to 5 minutes** after `apply` for the boot script to finish, then:

```powershell
terraform output
curl.exe http://<public-ip>/health
```

Expected: `{"status":"ok", ... "storage":{"notes":"dynamodb","files":"s3"}}`. Open `terraform output site_url` in a browser, add a note and attach a file.

If the page is not up yet, watch the boot script:

```powershell
ssh -i "$HOME\.ssh\id_ed25519" ubuntu@<public-ip>
sudo tail -f /var/log/cloud-init-output.log
```

## Stage 4: Verify every layer

| Check | Command or place | Expected |
| --- | --- | --- |
| App service | `systemctl status cloud-app --no-pager` (on server) | active (running) |
| Resource limits | `systemctl show cloud-app -p MemoryMax -p CPUQuotaPerSecUSec` | `MemoryMax=314572800` (300 MB) and `800ms` |
| Database | DynamoDB, Tables, `cloud-web-app-notes`, Explore items | your note is there |
| Storage | S3, the uploads bucket, `notes/<id>/...` | your attachment is there |
| Logs | CloudWatch, Log groups, `/cloud-web-app/app` | JSON request lines |
| Metrics | CloudWatch, Metrics, `CloudNotes` namespace | mem_used_percent |
| Secret | `aws ssm get-parameter ... --with-decryption` | the admin key |
| Protected delete | see below | 401 without key, 204 with it |
| Firewall | `Test-NetConnection <ip> -Port 3000` | fails (app is not exposed) |

Protected delete:

```powershell
$key = aws ssm get-parameter --name /cloud-web-app/admin-key --with-decryption --query Parameter.Value --output text
curl.exe -i -X DELETE http://<ip>/api/notes/<note-id>                      # 401
curl.exe -i -X DELETE -H "x-admin-key: $key" http://<ip>/api/notes/<note-id>   # 204
```

Do not screenshot or share the key itself.

## Updating the app after a change

Push to GitHub, then on the server:

```bash
cd /opt/cloud-app/src && sudo -u cloudapp git pull
cd app && sudo -u cloudapp npm ci --omit=dev
sudo systemctl restart cloud-app
```

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Site not loading after 5 minutes | Boot script failed | `sudo tail -100 /var/log/cloud-init-output.log` |
| `git clone` failed in the log | Repo not pushed, wrong `repo_url`, or private repo | Push it, make it public, then `terraform apply` again |
| `502 Bad Gateway` | App not running | `journalctl -u cloud-app -n 50` |
| App exits at startup | Cannot read the SSM parameter | Check the instance has its role: `aws sts get-caller-identity` on the server |
| `/health` shows `memory` / `disk` | Env file not loaded | Check `/etc/cloud-app.env`, restart the service |
| No alarm emails | SNS subscription not confirmed | Confirm the email |
| SSH times out | Your IP changed | Update `my_ip_cidr`, `terraform apply` |
| `terraform apply` budget error (AccessDenied) | IAM user lacks Budgets permission | Add `budgets:*` to your user, or ask me to make the budget optional |

## Keep it live, then clean up

The portal's **Live Website** field needs a working URL, so **keep the server running until your Module 3 submission is approved**. While it runs:

- Check **Billing, Free Tier** and the budget emails.
- The page accepts public notes, so the rate limits and upload rules above protect it.

When you are done:

```powershell
terraform destroy       # type yes
```

That removes everything, including the bucket contents. Confirm in the EC2 console that the instance is terminated.
