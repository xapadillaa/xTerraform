
// just in case need a specific version of Terraform or aws provider
/*
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.58.0"
    }
  }
}
*/


# Make sure to set execute "AWS configure" to set AWS credentials. Otherways you will get a auhentication error
provider "aws" {
  region = "us-west-1"
}

variable "provisioning_ec2" {
  description = "Path to the script that will install first set up in the server."
  type        = string
  default     = "/scripts/ec2_dependecies.sh"
}

variable "server_ami" {
  description = "AMI to use"
  type        = string
  default     = "ami-032cd1a6d943449a4"
}

variable "server_port" {
  description = "The port the server will use for HTTP request"
  type        = number
  default     = 80
}

data "http" "my_ip" {
  url = "https://checkip.amazonaws.com/"
}

// EC2 instances require a Segurity Group definition
resource "aws_security_group" "ec2_demo_sg" {
  name        = "EC2-DEMO-SG"
  description = "Security group for EC2 instances"


  #We set all Traffic will be allow from ALB not for anyone at internet

  # Allow HTTP from anywhere
  ingress {
    description     = "HTTP from internet"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.demo_alb_security_group.id]
    #cidr_blocks = [aws_security_group.demo_alb_security_group.id]
  }

  # Allow HTTPS from anywhere
  ingress {
    description     = "HTTPS from internet"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.demo_alb_security_group.id]
    #cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow SSH from the office network only
  ingress {
    description = "SSH from my laptop in the office"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"

    #Only current IP address will have access to ec2 from ssh 
    cidr_blocks = ["${chomp(data.http.my_ip.response_body)}/32"]
  }
}

// aws launch configuration is deprecated, use aws template 
resource "aws_launch_template" "demo_launch_template" {
  name                   = "DEMO-LT"
  description            = "Launch template configuration"
  image_id               = var.server_ami
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.ec2_demo_sg.id]

  lifecycle {
    create_before_destroy = true
  }

  user_data = base64encode(var.provisioning_ec2)
}

// Auto Scaling Group require a configuration to be launched. What you configure here is the EC2 instanes that will integrate 
// the groups of EC2 instances for the ASG


resource "aws_autoscaling_group" "demo_autoscaling_group" {

  vpc_zone_identifier = data.aws_subnets.default.ids

  launch_template {
    id      = aws_launch_template.demo_launch_template.id
    version = "$Latest"
  }

  //launch_configuration = aws_launch_configuration.asg_launch_configuration.name
  desired_capacity = 2
  min_size         = 1
  max_size         = 4

}


//this data source fetch default VPC set in the AWS 
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}


/*
 There are exist three types of load balancers n AWS :
 - Application load balancer
 - Networking load balancer
 - classic load balancer
*/

//Create AWS Application Load Balancer
resource "aws_lb" "demo_application_load_balancer" {
  name               = "DEMO-ALB"
  load_balancer_type = "application"
  subnets            = data.aws_subnets.default.ids

  //see sg resource for the ALB
  security_groups = [aws_security_group.demo_alb_security_group.id]
}

/* ALB consist of several part

 listener
 listener rule
 target groups
*/

// create listerner for the ALB
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.demo_application_load_balancer.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      status_code  = 404
      message_body = "404: page not found"
    }
  }
}

// set SG for ALB
resource "aws_security_group" "demo_alb_security_group" {
  name = "DEMO-ALB-SG"

  // allow  inbound HTTP request
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

// ALB target grouptarget
resource "aws_lb_target_group" "demo_alb_target_group" {
  name     = "DEMO-ALB-TG"
  port     = var.server_port
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 3
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
}


// Set ALB Listener rule
resource "aws_lb_listener_rule" "demo_alb_listener_rule" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  condition {
    path_pattern {
      values = ["*"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.demo_alb_target_group.arn
  }

}

output "alb_name" {
  value       = aws_lb.demo_application_load_balancer.name
  description = "The domain name of the load balancer"
}

output "local_ip_address" {
  value       = chomp(data.http.my_ip.response_body)
  description = "Local IP Address"
}

output "alb_dns_name" {
  value       = aws_lb.demo_application_load_balancer.dns_name
  description = "ALB dns name"
}