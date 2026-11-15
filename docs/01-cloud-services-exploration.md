# 1. Exploring core cloud services

Module 3 asks for a working knowledge of six service categories. This page explains each one, what it is for, and where it appears in this project. The app deployed here touches all six.

| Category | AWS service | Role in this project |
| --- | --- | --- |
| Compute | EC2 | Runs the Node.js app behind nginx |
| Object storage | S3 | Stores note attachments (uploaded files) |
| Managed database | DynamoDB | Stores the notes |
| Virtual networking | VPC, subnet, internet gateway, security group | Decides who can reach the server |
| IAM | Role, policy, instance profile | Gives the server its permissions without stored keys |
| Monitoring | CloudWatch Logs, metrics, alarms | Shows what the app is doing and alerts on problems |

## 1.1 Compute

Compute is where your code runs. AWS offers three main styles:

| Style | Service | You manage | Good for |
| --- | --- | --- | --- |
| Virtual machine | EC2 | OS, runtime, app | Full control, long-running apps (used here) |
| Container | ECS / EKS | Container image | Many services, consistent packaging |
| Serverless | Lambda | Function code only | Short event-driven tasks, pay per call |

This project uses a single `t3.micro` EC2 instance running Ubuntu 24.04. It is the simplest way to see every layer (OS, service manager, reverse proxy, app). The cost of that control is that patching and capacity are your job.

## 1.2 Object storage (S3)

S3 stores files as **objects** in **buckets**, each object identified by a key such as `notes/<id>/photo.png`. It is durable, cheap and accessed over HTTP, but it is not a file system and not a database.

- **Private by default.** The bucket here has all four Block Public Access settings on, so files are only reachable through the app and its IAM role.
- **Encrypted at rest** with SSE-S3 (AES-256).
- **Lifecycle rule** expires uploads after 30 days.
- Storage classes (Standard, Infrequent Access, Glacier) trade retrieval speed for price. Standard is right for an app serving files.

## 1.3 Managed databases

A managed database means AWS runs the servers, backups and patching.

| | DynamoDB | RDS |
| --- | --- | --- |
| Model | Key-value / document (NoSQL) | Relational (PostgreSQL, MySQL, ...) |
| Scaling | Automatic, pay per request in on-demand mode | Pick an instance size |
| Queries | By key and indexes | Full SQL, joins |
| Used here | Yes, table `cloud-web-app-notes` keyed by `id` | No |

DynamoDB was chosen because it needs no server to size or patch and fits a simple notes list. RDS would be the better choice for relational data such as users, orders and reports. The app uses a `Scan` to list notes, which is fine for a small table; a bigger table would need a key design that supports `Query`.

## 1.4 Virtual networking

Everything runs inside a **VPC**, your private network in AWS.

| Piece | What it does | Here |
| --- | --- | --- |
| VPC | Isolated network with an address range | The default VPC |
| Subnet | A slice of the VPC in one availability zone | A default public subnet |
| Route table + internet gateway | Sends internet traffic in and out | Default, already attached |
| Security group | Stateful firewall around the instance | 80 from anywhere, 22 from my IP only |
| Network ACL | Stateless firewall at subnet level | Left at the default (allow all) |

Traffic flow: browser, port 80, security group, `ufw` on the server, nginx, the app on `127.0.0.1:3000`. Port 3000 is never exposed; only nginx talks to it.

## 1.5 IAM (identity and access management)

IAM controls **who** can do **what** on **which** resource.

- **Users** are people (your `foncho-afa` user runs Terraform).
- **Roles** are identities that services assume and receive temporary credentials for. The server uses a role through an **instance profile**, so there are **no access keys on the server**.
- **Policies** list allowed actions. Ours allows only: read and write the one DynamoDB table, put/get/delete objects in the one bucket, and read the one SSM parameter. Anything else is denied by default.

Why it matters: if the app is compromised, the attacker only gets those few permissions, not your whole account. Never put access keys in code, in the repo, or in `user_data`.

## 1.6 Monitoring (CloudWatch)

| Tool | Answers | Here |
| --- | --- | --- |
| Metrics | "How busy is it?" | EC2 CPU, plus memory and disk from the CloudWatch agent |
| Logs | "What happened?" | App JSON logs and nginx access logs in log group `/cloud-web-app/app` |
| Alarms | "Tell me when it is wrong" | CPU above 80% and failed status checks, emailed through SNS |

Logs and metrics are different things: a metric is a number over time, a log is a record of one event.

## 1.7 Explore it yourself

Do these in the console first, then repeat with the CLI. Take the screenshots listed in `screenshots/README.md`.

| Category | Console path | CLI |
| --- | --- | --- |
| Compute | EC2, Instances | `aws ec2 describe-instances --query "Reservations[].Instances[].[InstanceId,InstanceType,State.Name,PublicIpAddress]" --output table` |
| Object storage | S3, Buckets | `aws s3 ls` then `aws s3 ls s3://<bucket>/ --recursive` |
| Database | DynamoDB, Tables, Explore items | `aws dynamodb list-tables` then `aws dynamodb scan --table-name cloud-web-app-notes` |
| Networking | VPC, Your VPCs, Subnets, Security groups | `aws ec2 describe-security-groups --group-names cloud-web-app-sg` |
| IAM | IAM, Roles, `cloud-web-app-role` | `aws iam get-role --role-name cloud-web-app-role` |
| Monitoring | CloudWatch, Log groups and Alarms | `aws logs describe-log-groups --log-group-name-prefix /cloud-web-app` |
