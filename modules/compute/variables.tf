variable "vpc_id" {
  description = "VPC ID from the networking module"
  type        = string
}

variable "subnet_ids" {
  description = "Public subnet IDs for the ALB and ASG"
  type        = list(string)
}

variable "environment" {
  description = "Environment name for tagging"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "min_size" {
  description = "ASG minimum size"
  type        = number
  default     = 2
}

variable "max_size" {
  description = "ASG maximum size"
  type        = number
  default     = 4
}

variable "desired_capacity" {
  description = "ASG desired capacity"
  type        = number
  default     = 2
}

variable "db_endpoint" {
  description = "RDS endpoint used by the app"
  type        = string
}

variable "db_name" {
  description = "Application database name"
  type        = string
}

variable "db_username_parameter_name" {
  description = "SSM Parameter Store name for the database username"
  type        = string
}

variable "db_password_parameter_name" {
  description = "SSM Parameter Store name for the database password"
  type        = string
}

variable "ssm_parameter_arns" {
  description = "SSM parameter ARNs the app instances may read"
  type        = list(string)
}
