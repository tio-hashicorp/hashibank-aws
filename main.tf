provider "aws" {
  #version = "6.11.0"
  region  = var.region
}

resource "aws_vpc" "hashibank" {
  cidr_block           = var.address_space
  enable_dns_hostnames = true

  tags = {
    name = "${var.prefix}-vpc-${var.region}"
    environment = "Production"
  }
}

resource "aws_subnet" "hashibank" {
  vpc_id     = aws_vpc.hashibank.id
  cidr_block = var.subnet_prefix

  tags = {
    name = "${var.prefix}-subnet"
  }
}

resource "aws_security_group" "hashibank" {
  name = "${var.prefix}-security-group"

  vpc_id = aws_vpc.hashibank.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
    prefix_list_ids = []
  }

  tags = {
    Name = "${var.prefix}-security-group"
  }
}

resource "random_id" "app-server-id" {
  prefix      = "${var.prefix}-hashibank-"
  byte_length = 8
}

resource "aws_internet_gateway" "hashibank" {
  vpc_id = aws_vpc.hashibank.id

  tags = {
    Name = "${var.prefix}-internet-gateway"
  }
}

resource "aws_route_table" "hashibank" {
  vpc_id = aws_vpc.hashibank.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.hashibank.id
  }
}

resource "aws_route_table_association" "hashibank" {
  subnet_id      = aws_subnet.hashibank.id
  route_table_id = aws_route_table.hashibank.id
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
}

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_eip" "hashibank" {
  instance = aws_instance.hashibank.id
}

resource "aws_eip_association" "hashibank" {
  instance_id   = aws_instance.hashibank.id
  allocation_id = aws_eip.hashibank.id
}

resource "aws_instance" "hashibank" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.hashibank.key_name
  associate_public_ip_address = true
  subnet_id                   = aws_subnet.hashibank.id
  vpc_security_group_ids      = [aws_security_group.hashibank.id]

  tags = {
    Name = "${var.prefix}-hashibank-instance"
    Department = "devOps"
    Billable = "yes"
  }
}

# We're using a little trick here so we can run the provisioner without
# destroying the VM. Do not do this in production.

# If you need ongoing management (Day N) of your virtual machines a tool such
# as Chef or Puppet is a better choice. These tools track the state of
# individual files and can keep them in the correct configuration.

# Here we do the following steps:
# Sync everything in files/ to the remote VM.
# Set up some environment variables for our script.
# Add execute permissions to our scripts.
# Run the deploy_app.sh script.
resource "null_resource" "configure-bank-app" {
  depends_on = [aws_eip_association.hashibank]

  triggers = {
    build_number = timestamp()
  }

  provisioner "file" {
    source      = "files/"
    destination = "/home/ubuntu/"

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = tls_private_key.hashibank.private_key_pem
      host        = aws_eip.hashibank.public_ip
    }
  }

  provisioner "remote-exec" {
    inline = [
      "sudo add-apt-repository universe",
      "sudo apt -y update",
      "sudo apt -y install apache2",
      "sudo systemctl start apache2",
      "sudo chown -R ubuntu:ubuntu /var/www/html",
      "chmod +x *.sh",
      "PLACEHOLDER=${var.placeholder} WIDTH=${var.width} HEIGHT=${var.height} PREFIX=${var.prefix} ./deploy_app.sh",
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = tls_private_key.hashibank.private_key_pem
      host        = aws_eip.hashibank.public_ip
      timeout = "10m"
    }
  }
}

resource "tls_private_key" "hashibank" {
  algorithm = "RSA"
}

locals {
  private_key_filename = "${random_id.app-server-id.dec}-ssh-key.pem"
}

resource "aws_key_pair" "hashibank" {
  key_name   = local.private_key_filename
  public_key = tls_private_key.hashibank.public_key_openssh
}
