data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  db_name                = "webscraper"
  db_username_param_name = "/project-genesis/db/username"
  db_password_param_name = "/project-genesis/db/password"
  selected_azs           = slice(data.aws_availability_zones.available.names, 0, 2)
  effective_azs          = length(var.availability_zones) > 0 ? var.availability_zones : local.selected_azs
}

module "networking" {
  source = "./modules/networking"

  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = local.effective_azs
}

resource "aws_db_subnet_group" "project_genesis" {
  name       = "project-genesis-db-subnet-group"
  subnet_ids = module.networking.private_subnet_ids

  tags = {
    Name = "project-genesis-db-subnet-group"
  }
}

resource "aws_security_group" "db_sg" {
  name        = "project-genesis-db-sg"
  description = "Allow PostgreSQL inbound traffic from the app security group"
  vpc_id      = module.networking.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "project-genesis-db-sg"
  }
}

resource "aws_security_group_rule" "db_from_app" {
  type                     = "ingress"
  description              = "PostgreSQL from app EC2"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.db_sg.id
  source_security_group_id = module.compute.app_security_group_id
}

resource "aws_db_instance" "postgres" {
  identifier             = "project-genesis-postgres"
  allocated_storage      = 20
  storage_type           = "gp2"
  engine                 = "postgres"
  engine_version         = "16"
  instance_class         = "db.t3.micro"
  db_name                = local.db_name
  username               = var.db_username
  password               = var.db_master_password
  db_subnet_group_name   = aws_db_subnet_group.project_genesis.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  publicly_accessible    = false
  skip_final_snapshot    = true

  tags = {
    Name = "project-genesis-postgres"
  }
}

resource "aws_ssm_parameter" "db_username" {
  name  = local.db_username_param_name
  type  = "String"
  value = var.db_username
}

resource "aws_ssm_parameter" "db_password" {
  name  = local.db_password_param_name
  type  = "SecureString"
  value = var.db_master_password
}

module "compute" {
  source = "./modules/compute"

  environment                = var.environment
  vpc_id                     = module.networking.vpc_id
  subnet_ids                 = module.networking.public_subnet_ids
  instance_type              = var.instance_type
  min_size                   = var.min_size
  max_size                   = var.max_size
  desired_capacity           = var.desired_capacity
  db_endpoint                = aws_db_instance.postgres.address
  db_name                    = local.db_name
  db_username_parameter_name = aws_ssm_parameter.db_username.name
  db_password_parameter_name = aws_ssm_parameter.db_password.name
  ssm_parameter_arns         = [aws_ssm_parameter.db_username.arn, aws_ssm_parameter.db_password.arn]
}

resource "aws_security_group" "private_instance" {
  name        = "project-genesis-private-instance-sg"
  description = "Allow outbound traffic only for the private EC2 instance"
  vpc_id      = module.networking.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "project-genesis-private-instance-sg"
  }
}

resource "aws_iam_role" "ssm" {
  name = "project-genesis-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm" {
  name = "project-genesis-ssm-profile"
  role = aws_iam_role.ssm.name
}

resource "aws_instance" "private_backend" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.instance_type
  subnet_id                   = module.networking.private_backend_subnet_id
  vpc_security_group_ids      = [aws_security_group.private_instance.id]
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.ssm.name

  tags = {
    Name = "project-genesis-private-ec2"
  }

  depends_on = [
    aws_iam_role_policy_attachment.ssm,
    module.networking
  ]

  lifecycle {
    ignore_changes = [ami]
  }
}
