output "alb_dns_name" {
  value = module.compute.alb_dns_name
}

output "vpc_id" {
  value = module.networking.vpc_id
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
