terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

# Provider settings
provider "aws" {
  region = "eu-central-1"
}

# VPC
resource "aws_vpc" "app-vpc" {
  cidr_block = "10.1.0.0/16"

  tags = {
    Name = "app-vpc"
  }
}

# Subnets
resource "aws_subnet" "subnets" {
  count                   = 2
  vpc_id                  = aws_vpc.app-vpc.id
  cidr_block              = "10.1.${count.index + 1}.0/24"
  availability_zone       = (count.index + 1) % 2 == 0 ? "eu-central-1b" : "eu-central-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "app-subnet-${count.index + 1}"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "app-igw" {
  vpc_id = aws_vpc.app-vpc.id

  tags = {
    Name = "app-igw"
  }
}

# Security Group and Rules
resource "aws_security_group" "app-sg" {
  name        = "app-sg"
  description = "Security Group for HTTP traffic."
  vpc_id      = aws_vpc.app-vpc.id
}

resource "aws_vpc_security_group_ingress_rule" "app-sg-inbound-rule" {
  security_group_id = aws_security_group.app-sg.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 80
  ip_protocol = "tcp"
  to_port     = 80
}

resource "aws_vpc_security_group_ingress_rule" "app-sg-inbound-rule_1" {
  security_group_id = aws_security_group.app-sg.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 22
  ip_protocol = "tcp"
  to_port     = 22
}

# Ultra wichtig !!!!!!! sonst wird nix installiert
resource "aws_vpc_security_group_egress_rule" "app-sg-outbound-rule" {
  security_group_id = aws_security_group.app-sg.id
    ip_protocol        = "-1"
    cidr_ipv4     = "0.0.0.0/0"
}

# Route Table and Associations
resource "aws_route_table" "public-route-table" {
  vpc_id = aws_vpc.app-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.app-igw.id
  }

  tags = {
    Name = "public-route-table"
  }
}

resource "aws_route_table_association" "route-table-association" {
  count          = 2
  subnet_id      = element(aws_subnet.subnets.*.id, count.index)
  route_table_id = aws_route_table.public-route-table.id
}

# EC2 Instances
resource "aws_instance" "app-server" {
  ami           = "ami-0122fd36a4f50873a"
  instance_type = "t2.micro"
  key_name      = "Webserver"
  user_data_replace_on_change = true

  vpc_security_group_ids = [aws_security_group.app-sg.id]
  subnet_id              = element(aws_subnet.subnets.*.id, 0)
  user_data              = file("install-employee-dir-app.sh")

  tags = {
    Name = "employee-app-server-1"
  }
}


# IAM 
# Dynamo DB
# S3 Bucket
# Loadbalancer
# Auto Scaling Group