terraform {
  backend "s3" {
    bucket       = "project-genesis-tf-state-vboxuser-98765"
    key          = "project-genesis/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "db_master_password" {
  description = "Master password for the PostgreSQL RDS instance"
  type        = string
  sensitive   = true
}

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

resource "aws_vpc" "project_genesis" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "project-genesis-vpc"
  }
}

resource "aws_internet_gateway" "project_genesis" {
  vpc_id = aws_vpc.project_genesis.id

  tags = {
    Name = "project-genesis-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.project_genesis.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "project-genesis-public-subnet"
  }
}

resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.project_genesis.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = false

  tags = {
    Name = "project-genesis-private-subnet"
  }
}

resource "aws_subnet" "private_db" {
  vpc_id                  = aws_vpc.project_genesis.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = false

  tags = {
    Name = "project-genesis-private-db-subnet"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.project_genesis.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.project_genesis.id
  }

  tags = {
    Name = "project-genesis-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.project_genesis.id

  tags = {
    Name = "project-genesis-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_db" {
  subnet_id      = aws_subnet.private_db.id
  route_table_id = aws_route_table.private.id
}

resource "aws_db_subnet_group" "project_genesis" {
  name       = "project-genesis-db-subnet-group"
  subnet_ids = [aws_subnet.private_db.id, aws_subnet.private.id]

  tags = {
    Name = "project-genesis-db-subnet-group"
  }
}

resource "aws_security_group" "app_sg" {
  name        = "project-genesis-app-sg"
  description = "Allow HTTP and SSH inbound traffic for the app EC2 instance"
  vpc_id      = aws_vpc.project_genesis.id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "project-genesis-app-sg"
  }
}

resource "aws_security_group" "db_sg" {
  name        = "project-genesis-db-sg"
  description = "Allow PostgreSQL inbound traffic from the app security group"
  vpc_id      = aws_vpc.project_genesis.id

  ingress {
    description     = "PostgreSQL from app EC2"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app_sg.id]
  }

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

resource "aws_security_group" "private_instance" {
  name        = "project-genesis-private-instance-sg"
  description = "Allow outbound traffic only for the private EC2 instance"
  vpc_id      = aws_vpc.project_genesis.id

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

resource "aws_db_instance" "postgres" {
  identifier             = "project-genesis-postgres"
  allocated_storage      = 20
  storage_type           = "gp2"
  engine                 = "postgres"
  engine_version         = "16"
  instance_class         = "db.t3.micro"
  db_name                = "webscraper"
  username               = "webscraper_user"
  password               = var.db_master_password
  db_subnet_group_name   = aws_db_subnet_group.project_genesis.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  publicly_accessible    = false
  skip_final_snapshot    = true

  tags = {
    Name = "project-genesis-postgres"
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

resource "aws_instance" "web" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.app_sg.id]
  associate_public_ip_address = true

  tags = {
    Name = "project-genesis-app-ec2"
  }
}

resource "aws_instance" "private_backend" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.private.id
  vpc_security_group_ids      = [aws_security_group.private_instance.id]
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.ssm.name

  tags = {
    Name = "project-genesis-private-ec2"
  }

  depends_on = [
    aws_iam_role_policy_attachment.ssm,
    aws_route_table_association.private
  ]
}

output "private_backend_instance_id" {
  value = aws_instance.private_backend.id
}

output "private_backend_public_ip" {
  value = aws_instance.private_backend.public_ip
}

output "private_backend_private_ip" {
  value = aws_instance.private_backend.private_ip
}
