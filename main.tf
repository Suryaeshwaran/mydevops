# Define the AWS provider configuration.
provider "aws" {
  region = "us-east-1"  # Replace with your desired AWS region.
}

variable "cidr" {
  default = "10.0.0.0/16"
}

resource "aws_key_pair" "mykey" {
  key_name   = "mykey"  # Replace with your desired key name
  public_key = file("~/.ssh/id_rsa.pub")  # This Key is already Created on Host using 'ssh-keygen -t rsa'
}

resource "aws_vpc" "myvpc" {
  cidr_block = var.cidr
}

resource "aws_subnet" "sub1" {
  vpc_id                  = aws_vpc.myvpc.id
  cidr_block              = "10.0.0.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.myvpc.id
}

resource "aws_route_table" "RT" {
  vpc_id = aws_vpc.myvpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "rta1" {
  subnet_id      = aws_subnet.sub1.id
  route_table_id = aws_route_table.RT.id
}

resource "aws_security_group" "webSg" {
  name   = "web"
  vpc_id = aws_vpc.myvpc.id

  ingress {
    description = "HTTP from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "SSH"
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
    Name = "Web-sg"
  }
}
resource "aws_instance" "server" {
  ami                    = "ami-0866a3c8686eaeeba"
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.mykey.key_name
  vpc_security_group_ids = [aws_security_group.webSg.id]
  subnet_id              = aws_subnet.sub1.id
  tags = {
    Name = "MyPublicApp"
  }
  connection {
    type        = "ssh"
    user        = "ubuntu"  # Replace with the appropriate username for your EC2 instance
    private_key = file("~/.ssh/id_rsa")  # Replace with the path to your private key
    host        = self.public_ip
  }
  # File provisioner to copy a file from local to the remote EC2 instance
  provisioner "file" {
    source      = "app.py"  # Replace with the path to your local file
    destination = "/home/ubuntu/app.py"  # Replace with the path on the remote instance
  }
  
  provisioner "remote-exec"{
    inline = [       
      "sudo apt-get update -y",  # Update package lists (for ubuntu)
      "sudo apt-get install -y python3", # Install python3
      "sudo apt-get install -y python3-pip",  # Install pip for python3
      "sudo apt-get install -y python3-flask", # Install Flask using python3
      # Writing the systemd service file using echo
      "echo '[Unit]' | sudo tee /etc/systemd/system/python-app.service",
      "echo 'Description=My Python App' | sudo tee -a /etc/systemd/system/python-app.service",
      "echo '[Service]' | sudo tee -a /etc/systemd/system/python-app.service",
      # Verify the path for python3 & app.py
      "echo 'ExecStart=/usr/bin/python3 /home/ubuntu/app.py' | sudo tee -a /etc/systemd/system/python-app.service",
      "echo 'Restart=always' | sudo tee -a /etc/systemd/system/python-app.service",
      "echo '[Install]' | sudo tee -a /etc/systemd/system/python-app.service",
      "echo 'WantedBy=multi-user.target' | sudo tee -a /etc/systemd/system/python-app.service",
      # Reloading systemd, starting and enabling the service
      "sudo systemctl daemon-reload",
      "sudo systemctl start python-app.service",
      "sudo systemctl enable python-app.service"  
       ]
  }
}

output "MyPublicApp" {
  value = aws_instance.server.public_ip
}