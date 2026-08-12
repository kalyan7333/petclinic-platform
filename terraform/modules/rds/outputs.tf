output "endpoint" {
  description = "RDS instance endpoint hostname"
  value       = aws_db_instance.this.address
}

output "port" {
  description = "RDS port"
  value       = aws_db_instance.this.port
}

output "db_instance_id" {
  description = "RDS instance identifier"
  value       = aws_db_instance.this.identifier
}

output "secret_arn" {
  description = "Secrets Manager ARN for RDS credentials"
  value       = aws_secretsmanager_secret.rds.arn
  sensitive   = true
}

output "db_name" {
  description = "Database name (petclinic)"
  value       = aws_db_instance.this.db_name
}

output "db_username" {
  description = "RDS master username"
  value       = aws_db_instance.this.username
}

output "connection_string" {
  description = "JDBC connection string for SPRING_DATASOURCE_URL"
  value       = "jdbc:mysql://${aws_db_instance.this.address}:3306/petclinic"
  sensitive   = true
}
