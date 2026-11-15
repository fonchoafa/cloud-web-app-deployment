# Screenshot checklist

Add PNG screenshots here before pushing. Blur your AWS account ID and never show the admin key.

| File | What it must show |
| --- | --- |
| `00-terraform-apply.png` | `terraform apply` complete with the outputs |
| `01-live-site.png` | The live site in the browser with a note and an attachment |
| `02-health-endpoint.png` | `/health` showing `dynamodb` and `s3` |
| `03-ec2-instance.png` | EC2 console: instance running |
| `04-security-group.png` | Inbound rules: 80 anywhere, 22 from my IP |
| `05-s3-bucket.png` | S3: the uploads bucket with the attachment object, and Block Public Access on |
| `06-dynamodb-items.png` | DynamoDB: Explore items showing the note |
| `07-iam-role.png` | IAM: `cloud-web-app-role` and its permission policy |
| `08-ssm-parameter.png` | SSM Parameter Store: `/cloud-web-app/admin-key` as SecureString (value hidden) |
| `09-cloudwatch-logs.png` | CloudWatch Logs: JSON log lines from the app |
| `10-cloudwatch-alarms.png` | CloudWatch alarms and the budget |
| `11-service-status.png` | `systemctl status cloud-app` and the resource limits |
| `12-delete-protected.png` | DELETE returns 401 without the key and 204 with it |
