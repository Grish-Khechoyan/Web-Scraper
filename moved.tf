moved {
  from = aws_vpc.project_genesis
  to   = module.networking.aws_vpc.project_genesis
}

moved {
  from = aws_internet_gateway.project_genesis
  to   = module.networking.aws_internet_gateway.project_genesis
}

moved {
  from = aws_subnet.public
  to   = module.networking.aws_subnet.public
}

moved {
  from = aws_subnet.public_secondary
  to   = module.networking.aws_subnet.public_secondary
}

moved {
  from = aws_subnet.private
  to   = module.networking.aws_subnet.private
}

moved {
  from = aws_subnet.private_db
  to   = module.networking.aws_subnet.private_db
}

moved {
  from = aws_route_table.public
  to   = module.networking.aws_route_table.public
}

moved {
  from = aws_route_table_association.public
  to   = module.networking.aws_route_table_association.public
}

moved {
  from = aws_route_table_association.public_secondary
  to   = module.networking.aws_route_table_association.public_secondary
}

moved {
  from = aws_route_table.private
  to   = module.networking.aws_route_table.private
}

moved {
  from = aws_route_table_association.private
  to   = module.networking.aws_route_table_association.private
}

moved {
  from = aws_route_table_association.private_db
  to   = module.networking.aws_route_table_association.private_db
}

moved {
  from = aws_security_group.app_sg
  to   = module.compute.aws_security_group.app_sg
}
