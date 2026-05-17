resource "aws_vpc" "project_genesis" {
  cidr_block           = var.vpc_cidr
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
  cidr_block              = var.public_subnet_cidrs[0]
  availability_zone       = var.availability_zones[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "project-genesis-public-subnet"
  }
}

resource "aws_subnet" "public_secondary" {
  vpc_id                  = aws_vpc.project_genesis.id
  cidr_block              = var.public_subnet_cidrs[1]
  availability_zone       = var.availability_zones[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "project-genesis-public-secondary-subnet"
  }
}

resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.project_genesis.id
  cidr_block              = var.private_subnet_cidrs[0]
  availability_zone       = var.availability_zones[1]
  map_public_ip_on_launch = false

  tags = {
    Name = "project-genesis-private-subnet"
  }
}

resource "aws_subnet" "private_db" {
  vpc_id                  = aws_vpc.project_genesis.id
  cidr_block              = var.private_subnet_cidrs[1]
  availability_zone       = var.availability_zones[0]
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

resource "aws_route_table_association" "public_secondary" {
  subnet_id      = aws_subnet.public_secondary.id
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
