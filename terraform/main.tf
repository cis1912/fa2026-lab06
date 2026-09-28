terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Points the AWS provider at LocalStack instead of real AWS.
# Nothing below this block ever leaves your machine.
provider "aws" {
  region = "us-east-1"

  access_key = "test"
  secret_key = "test"

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    ec2 = "http://localhost:4566"
  }
}

resource "aws_vpc" "main" {
  cidr_block = <FILL_IN> # e.g. "10.0.0.0/16"
}

resource "aws_subnet" "main" {
  # Reference the VPC resource above instead of hardcoding an ID —
  # Terraform uses this to know it must create the VPC first.
  vpc_id     = <FILL_IN>
  cidr_block = "10.0.1.0/24"
}

resource "aws_security_group" "main" {
  name   = "lab05-sg"
  vpc_id = <FILL_IN>

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "subnet_id" {
  value = aws_subnet.main.id
}

output "security_group_id" {
  value = aws_security_group.main.id
}
