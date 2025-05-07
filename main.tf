provider "aws" {
  region = "us-east-1"
}

# --- S3 Bucket for Terraform State ---
# resource "aws_s3_bucket" "terraform_state" {
#   bucket = "gitlab-terraform-state-bucket"
#   acl    = "private"

#   tags = {
#     Name = "GitLab Terraform State Bucket"
#   }
# }

# --- Backend Configuration ---
terraform {
  backend "s3" {
    bucket = "gitlab-terraform-state-bucket-demo"  # Use a hardcoded bucket name here
    key    = "gitlab/terraform.tfstate"
    region = "us-east-1"
    encrypt = true
  }
}

# --- VPC ---
resource "aws_vpc" "gitlab_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "gitlab-vpc"
  }
}

# --- Internet Gateway ---
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.gitlab_vpc.id

  tags = {
    Name = "gitlab-igw"
  }
}

# --- Public Subnets ---
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.gitlab_vpc.id
  cidr_block              = "10.0.0.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "gitlab-public-a"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.gitlab_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "gitlab-public-b"
  }
}

# --- Private Subnets ---
resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.gitlab_vpc.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "gitlab-private-a"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.gitlab_vpc.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "gitlab-private-b"
  }
}

# --- NAT Gateway ---
resource "aws_eip" "nat_eip" {
  vpc = true
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_b.id

  tags = {
    Name = "gitlab-nat"
  }

  depends_on = [aws_internet_gateway.gw]
}

# --- Route Tables ---
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.gitlab_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "gitlab-public-rt"
  }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.gitlab_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "gitlab-private-rt"
  }
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}

# --- Security Group for GitLab EC2 ---
resource "aws_security_group" "gitlab_sg" {
  name        = "gitlab-sg"
  description = "Allow HTTP, HTTPS, SSH"
  vpc_id      = aws_vpc.gitlab_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["103.244.175.22/32"]
  }

  ingress {
    from_port   = 80
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
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
    Name = "gitlab-security-group"
  }
}

# --- EBS Volume for GitLab Data ---
resource "aws_ebs_volume" "gitlab_data" {
  availability_zone = "us-east-1a"
  size              = 50
  type              = "gp3"
  tags = {
    Name = "gitlab-data-volume"
  }
}

# --- EC2 Instance for GitLab ---
resource "aws_instance" "gitlab" {
  ami                         = "ami-0fc5d935ebf8bc3bc" # Ubuntu 22.04 LTS
  instance_type               = "c5.xlarge"
  subnet_id                   = aws_subnet.public_a.id
  vpc_security_group_ids      = [aws_security_group.gitlab_sg.id]
  associate_public_ip_address = true

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name = "gitlab-omnibus"
  }

  user_data = file("gitlab-userdata.sh")

  depends_on = [aws_internet_gateway.gw]
}

resource "aws_volume_attachment" "ebs_att" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.gitlab_data.id
  instance_id = aws_instance.gitlab.id
  force_detach = true
}

# --- RDS Security Group ---
resource "aws_security_group" "gitlab_rds_sg" {
  name        = "gitlab-rds-sg"
  description = "Allow PostgreSQL from GitLab EC2"
  vpc_id      = aws_vpc.gitlab_vpc.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.gitlab_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "gitlab-rds-sg"
  }
}

# --- RDS Subnet Group (Public) ---
resource "aws_db_subnet_group" "gitlab" {
  name       = "gitlab-db-subnet-group"
  subnet_ids = [aws_subnet.public_a.id, aws_subnet.public_b.id]

  tags = {
    Name = "GitLab RDS Subnet Group"
  }
}

# --- RDS PostgreSQL ---
resource "aws_db_instance" "gitlab" {
  identifier             = "gitlab-postgres"
  allocated_storage      = 20
  storage_type           = "gp3"
  engine                 = "postgres"
  engine_version         = "15"
  instance_class         = "db.t3.micro"
  db_name                = "gitlabdb"
  username               = "gitlabadmin"
  password               = "StrongPassword123!"
  publicly_accessible    = true
  skip_final_snapshot    = true
  vpc_security_group_ids = [aws_security_group.gitlab_rds_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.gitlab.name

  tags = {
    Name = "GitLab RDS"
  }
}
resource "aws_security_group" "gitlab_runner_sg" {
  name        = "gitlab-runner-sg"
  description = "Allow SSH and GitLab Runner connectivity"
  vpc_id      = aws_vpc.gitlab_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/32"]  # Replace with your IP
  }

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.gitlab_sg.id] # Allow connection to GitLab HTTPS
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "gitlab-runner-sg"
  }
}

resource "aws_instance" "gitlab_runner" {
  ami                         = "ami-0fc5d935ebf8bc3bc" # Ubuntu 22.04
  instance_type               = "t3.small"
  subnet_id                   = aws_subnet.public_b.id
  vpc_security_group_ids      = [aws_security_group.gitlab_runner_sg.id]
  associate_public_ip_address = true

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name = "gitlab-runner"
  }

  user_data = file("gitlab-runner-userdata.sh") # Optional shell script to auto-install runner

  depends_on = [aws_internet_gateway.gw]
}
