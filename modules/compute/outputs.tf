output "alb_dns_name" {
  value = aws_lb.app.dns_name
}

output "asg_name" {
  value = aws_autoscaling_group.app.name
}

output "app_security_group_id" {
  value = aws_security_group.app_sg.id
}
