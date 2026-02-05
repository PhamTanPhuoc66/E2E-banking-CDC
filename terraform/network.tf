######### VPC #########
resource "aws_vpc" "e2e_vpc" {
  cidr_block       = var.vpc_cidr_block
  instance_tenancy = "default"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "e2e_vpc"
  }
}

######### Subnets #########
###private###
resource "aws_subnet" "private_subnet" {
  vpc_id     = aws_vpc.e2e_vpc.id
  cidr_block = var.private_subnet_cidr_block
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = {
    Name = "private_subnet"
  }
}

###public###
resource "aws_subnet" "public_subnet" {
  vpc_id     = aws_vpc.e2e_vpc.id
  cidr_block = var.public_subnet_cidr_block
  map_public_ip_on_launch = true 

  tags = {
    Name = "public_subnet"
  }
}

######### Internet Gateway #########
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.e2e_vpc.id

  tags = {
    Name = "e2e_igw"
  }
}

######### NAT Gateway #########
resource "aws_eip" "nat_eip" {
  domain       = "vpc"

  tags = {
    Name = "nat_eip"
  }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet.id

  tags = {
    Name = "gw NAT"
  }


  depends_on = [aws_internet_gateway.igw]
}
######### Route Table #########
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.e2e_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public_rt"
  }
}
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.e2e_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "private_rt"
  }
}
