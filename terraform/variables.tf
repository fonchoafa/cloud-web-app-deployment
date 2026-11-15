variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Name prefix for every resource"
  type        = string
  default     = "cloud-web-app"
}

variable "instance_type" {
  description = "Free tier eligible type (t2.micro or t3.micro depending on your account)"
  type        = string
  default     = "t3.micro"
}

variable "public_key_path" {
  description = "Path to your SSH PUBLIC key"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "my_ip_cidr" {
  description = "Your public IP in CIDR form for SSH, for example 203.0.113.7/32"
  type        = string

  validation {
    condition     = can(cidrhost(var.my_ip_cidr, 0)) && var.my_ip_cidr != "0.0.0.0/0"
    error_message = "Use your own IP as a /32 CIDR, not 0.0.0.0/0."
  }
}

variable "alert_email" {
  description = "Email that receives CloudWatch alarms and budget alerts"
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_email))
    error_message = "Enter a valid email address."
  }
}

variable "repo_url" {
  description = "Public Git URL the server clones the app from (push the repo before applying)"
  type        = string
  default     = "https://github.com/fonchoafa/cloud-web-app-deployment.git"
}

variable "repo_branch" {
  description = "Branch to deploy"
  type        = string
  default     = "main"
}

variable "monthly_budget_usd" {
  description = "Monthly cost budget in USD"
  type        = number
  default     = 5
}
