# =========================================
# Main Terraform Configuration
# =========================================
# This file contains:
# - Provider configuration
# - VPC and networking resources
# - Security group configuration
#
# The infrastructure defined here provides the base
# networking layer for the AWS Batch environment.
# =========================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# VPC Configuration
resource "aws_vpc" "batch_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "batch-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "batch_igw" {
  vpc_id = aws_vpc.batch_vpc.id

  tags = {
    Name = "batch-igw"
  }
}

# Public Subnet
resource "aws_subnet" "batch_subnet" {
  vpc_id                  = aws_vpc.batch_vpc.id
  cidr_block              = var.subnet_cidr
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"

  tags = {
    Name = "batch-subnet"
  }
}

# Route Table
resource "aws_route_table" "batch_rt" {
  vpc_id = aws_vpc.batch_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.batch_igw.id
  }

  tags = {
    Name = "batch-rt"
  }
}

# Route Table Association
resource "aws_route_table_association" "batch_rta" {
  subnet_id      = aws_subnet.batch_subnet.id
  route_table_id = aws_route_table.batch_rt.id
}

# Security Group
resource "aws_security_group" "batch_sg" {
  name        = "batch-security-group"
  description = "Security group for AWS Batch compute environment"
  vpc_id      = aws_vpc.batch_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "batch-sg"
  }
} 