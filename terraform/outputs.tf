output "public_ip" {
  description = "Public IP of the web server"
  value       = aws_instance.app.public_ip
}

output "site_url" {
  description = "The live website"
  value       = "http://${aws_instance.app.public_ip}"
}

output "health_url" {
  value = "http://${aws_instance.app.public_ip}/health"
}

output "ssh_command" {
  value = "ssh -i ~/.ssh/id_ed25519 ubuntu@${aws_instance.app.public_ip}"
}

output "notes_table" {
  value = aws_dynamodb_table.notes.name
}

output "uploads_bucket" {
  value = aws_s3_bucket.uploads.bucket
}

output "log_group" {
  value = aws_cloudwatch_log_group.app.name
}

output "admin_key_command" {
  description = "Run this to read the admin key (the value itself is never printed here)"
  value       = "aws ssm get-parameter --name ${local.secret_param} --with-decryption --query Parameter.Value --output text --region ${var.region}"
}
