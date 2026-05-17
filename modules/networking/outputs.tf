output "vpc_id" {
  value = aws_vpc.project_genesis.id
}

output "public_subnet_ids" {
  value = [aws_subnet.public.id, aws_subnet.public_secondary.id]
}

output "private_subnet_ids" {
  value = [aws_subnet.private_db.id, aws_subnet.private.id]
}

output "private_backend_subnet_id" {
  value = aws_subnet.private.id
}

output "private_route_table_association_id" {
  value = aws_route_table_association.private.id
}
