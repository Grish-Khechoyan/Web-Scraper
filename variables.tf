variable "db_master_password" {
  description = "Master password for the PostgreSQL RDS instance"
  type        = string
  sensitive   = true
}
