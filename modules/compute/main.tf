data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_region" "current" {}

resource "aws_security_group" "alb_sg" {
  name        = "project-genesis-alb-sg"
  description = "Allow HTTP inbound traffic for the application load balancer"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
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
    Name = "project-genesis-alb-sg"
  }
}

resource "aws_security_group" "app_sg" {
  name        = "project-genesis-app-sg"
  description = "Allow HTTP and SSH inbound traffic for the app EC2 instance"
  vpc_id      = var.vpc_id

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

resource "aws_lb" "app" {
  name               = "project-genesis-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = var.subnet_ids

  tags = {
    Name = "project-genesis-alb"
  }
}

resource "aws_lb_target_group" "app" {
  name     = "project-genesis-app-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    path                = "/health"
    port                = "80"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "project-genesis-app-tg"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_iam_role" "app_ssm" {
  name = "project-genesis-app-ssm-role"

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

resource "aws_iam_role_policy" "app_ssm_parameters" {
  name = "project-genesis-app-ssm-parameters"
  role = aws_iam_role.app_ssm.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ssm:GetParameter"
        Resource = var.ssm_parameter_arns
      },
      {
        Effect   = "Allow"
        Action   = "kms:Decrypt"
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "ssm.${data.aws_region.current.region}.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_instance_profile" "app_ssm" {
  name = "project-genesis-app-ssm-profile"
  role = aws_iam_role.app_ssm.name
}

resource "aws_launch_template" "app" {
  name_prefix   = "project-genesis-app-"
  image_id      = data.aws_ami.amazon_linux_2.id
  instance_type = var.instance_type

  vpc_security_group_ids = [aws_security_group.app_sg.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.app_ssm.name
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              set -euo pipefail

              if command -v dnf >/dev/null 2>&1; then
                dnf update -y
                dnf install -y git docker awscli
                dnf install -y docker-compose-plugin || dnf install -y docker-compose
              elif command -v yum >/dev/null 2>&1; then
                yum update -y
                yum install -y git docker curl awscli
                curl -SL https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-x86_64 -o /usr/local/bin/docker-compose
                chmod +x /usr/local/bin/docker-compose
                mkdir -p /usr/local/lib/docker/cli-plugins
                ln -sf /usr/local/bin/docker-compose /usr/local/lib/docker/cli-plugins/docker-compose
              else
                apt-get update -y
                apt-get install -y git docker.io docker-compose awscli
              fi

              systemctl enable --now docker

              cd /opt
              if [ ! -d Web-Scraper ]; then
                git clone https://github.com/Grish-Khechoyan/Web-Scraper.git
              fi

              cd Web-Scraper
              git pull --ff-only

              export AWS_DEFAULT_REGION="${data.aws_region.current.region}"
              DB_USERNAME="$(aws ssm get-parameter --name "${var.db_username_parameter_name}" --query Parameter.Value --output text)"
              DB_PASSWORD="$(aws ssm get-parameter --name "${var.db_password_parameter_name}" --with-decryption --query Parameter.Value --output text)"

              cat > .env <<ENV
              DB_USERNAME=$DB_USERNAME
              DB_PASSWORD=$DB_PASSWORD
              DB_HOST=${var.db_endpoint}
              DB_NAME=${var.db_name}
              DATABASE_URL=postgres://$DB_USERNAME:$DB_PASSWORD@${var.db_endpoint}/${var.db_name}
              ENV

              if docker compose version >/dev/null 2>&1; then
                docker compose up -d
              else
                docker-compose up -d
              fi
              EOF
  )

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "project-genesis-asg-app"
    }
  }

  tags = {
    Name = "project-genesis-app-launch-template"
  }
}

resource "aws_autoscaling_group" "app" {
  name                = "project-genesis-app-asg"
  min_size            = var.min_size
  max_size            = var.max_size
  desired_capacity    = var.desired_capacity
  vpc_zone_identifier = var.subnet_ids
  target_group_arns   = [aws_lb_target_group.app.arn]
  health_check_type   = "ELB"

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "project-genesis-asg-app"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_policy" "app_cpu_target" {
  name                   = "project-genesis-app-cpu-target"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = 50.0
  }
}
