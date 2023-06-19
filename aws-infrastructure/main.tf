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

resource "aws_vpc_security_group_egress_rule" "app-sg-outbound-rule" {
  security_group_id = aws_security_group.app-sg.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
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

# IAM Role, Policies and Profile
resource "aws_iam_role" "s3_dynamo_db_full_access" {
  name = "S3DynamoDBFullAccessRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "s3_full_access" {
  role       = aws_iam_role.s3_dynamo_db_full_access.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role_policy_attachment" "dynamodb_full_access" {
  role       = aws_iam_role.s3_dynamo_db_full_access.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2-profile"
  role = aws_iam_role.s3_dynamo_db_full_access.name
}

# Dynamo DB Table
resource "aws_dynamodb_table" "employees" {
  name           = "Employees"
  billing_mode   = "PROVISIONED"
  hash_key       = "id"
  read_capacity  = 20
  write_capacity = 20

  attribute {
    name = "id"
    type = "S"
  }
}

# S3 Bucket and Policy
resource "aws_s3_bucket" "employee-photo-bucket" {
  bucket        = "employee-photo-bucket-ef-24241"
  force_destroy = true
  
}

resource "aws_s3_bucket_public_access_block" "app-s3-public-access" {
  bucket = aws_s3_bucket.employee-photo-bucket.id

  block_public_acls   = false
  block_public_policy = false
}

resource "aws_s3_bucket_policy" "allow_s3_read_access" {
  bucket = aws_s3_bucket.employee-photo-bucket.id
  policy = data.aws_iam_policy_document.allow_s3_read_access.json
}

data "aws_iam_policy_document" "allow_s3_read_access" {
  statement {
    sid = "AllowS3ReadAccess"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::032798421413:role/S3DynamoDBFullAccessRole"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.employee-photo-bucket.arn,
      "${aws_s3_bucket.employee-photo-bucket.arn}/*",
    ]
  }
}

# Loadbalancer, Target Group and Target Group Listener
resource "aws_lb" "app-lb" {
  name               = "app-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.load-balancer-sg.id]
  subnets            = [aws_subnet.subnets[0].id, aws_subnet.subnets[1].id]

}

resource "aws_lb_target_group" "app-target-group" {
  name     = "app-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.app-vpc.id

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 30
    interval            = 40
    port                = 80
  }
}

resource "aws_lb_listener" "app-lb-listener" {
  load_balancer_arn = aws_lb.app-lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_lb_target_group.app-target-group.arn
    type             = "forward"
  }
}

resource "aws_lb_listener_rule" "listener_rule" {
  depends_on   = [aws_lb_target_group.app-target-group]
  listener_arn = aws_lb_listener.app-lb-listener.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app-target-group.arn
  }

  condition {
    path_pattern {
      values = ["/"]
    }
  }
}

resource "aws_security_group" "load-balancer-sg" {
  name        = "load-balancer-sg"
  description = "Security Group for HTTP traffic."
  vpc_id      = aws_vpc.app-vpc.id
}

resource "aws_vpc_security_group_ingress_rule" "load-balancer-sg-inbound-rule" {
  security_group_id = aws_security_group.load-balancer-sg.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 80
  ip_protocol = "tcp"
  to_port     = 80
}

resource "aws_vpc_security_group_egress_rule" "load-balancer-sg-outbound-rule" {
  security_group_id = aws_security_group.load-balancer-sg.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# Launch Template
resource "aws_launch_template" "app-server-launch-template" {
  name          = "app-server-template"
  image_id      = "ami-0122fd36a4f50873a"
  instance_type = "t2.micro"

  key_name  = "Webserver"
  user_data = filebase64("install-employee-dir-app.sh")

  iam_instance_profile {
    arn = aws_iam_instance_profile.ec2_profile.arn
  }

  network_interfaces {
    security_groups             = [aws_security_group.app-sg.id]
    associate_public_ip_address = true
    delete_on_termination       = true
  }
}

# EC2 Instances Vars
variable "min_instance_count" {
  description = "Number of minimum instances to create"
  default     = 2
}

variable "max_instance_count" {
  description = "Number of maximum instances to create"
  default     = 4
}

variable "instance_name" {
  description = "Prefix for instance names"
  default     = "employee-dir-app-server"
}

# Auto Scaling Group and Policy
resource "aws_autoscaling_group" "app-auto-scaling-group" {
  name     = "app-auto-scaling-group"
  min_size = var.min_instance_count
  max_size = var.max_instance_count

  health_check_type         = "ELB"
  health_check_grace_period = 300
  target_group_arns         = [aws_lb_target_group.app-target-group.arn]

  launch_template {
    id      = aws_launch_template.app-server-launch-template.id
    version = "$Latest"
  }

  vpc_zone_identifier = [aws_subnet.subnets[0].id, aws_subnet.subnets[1].id]

  tag {
    key                 = "Name"
    value               = var.instance_name
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_policy" "app-auto-scaling-policy" {
  name                      = "app-auto-scaling-policy"
  policy_type               = "TargetTrackingScaling"
  autoscaling_group_name    = aws_autoscaling_group.app-auto-scaling-group.name
  estimated_instance_warmup = 300

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"

    }

    target_value = 60.0

  }
}

# Auto Scaling Notifications
resource "aws_sns_topic" "app-server-scaling-topic" {
  name = "app-server-scaling-topic"
}

resource "aws_sns_topic_subscription" "app-server-scalling-sub" {
  topic_arn = aws_sns_topic.app-server-scaling-topic.arn
  protocol  = "email"
  endpoint  = "erik-falk@web.de"
}

resource "aws_autoscaling_notification" "app-server-asg-notifications" {
  group_names = [
    aws_autoscaling_group.app-auto-scaling-group.name
  ]

  notifications = [
    "autoscaling:EC2_INSTANCE_LAUNCH",
    "autoscaling:EC2_INSTANCE_TERMINATE",
    "autoscaling:EC2_INSTANCE_LAUNCH_ERROR",
    "autoscaling:EC2_INSTANCE_TERMINATE_ERROR",
  ]

  topic_arn = aws_sns_topic.app-server-scaling-topic.arn
}

# Monitoring
resource "aws_cloudwatch_dashboard" "app_dashboard" {
  dashboard_name = "employee-app-dashboard"

  dashboard_body = jsonencode(
    {
      "widgets" : [
        {
          "type" : "text",
          "x" : 0,
          "y" : 0,
          "width" : 5,
          "height" : 1
          "properties" : {
            "markdown" : "### Welcome to the Employee Directory App Dashboard"
          }
        },
        {
          "type" : "metric",
          "x" : 0,
          "y" : 3,
          "width" : 12,
          "height" : 6,
          "properties" : {
            "metrics" : [
              ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", "app-auto-scaling-group", { "label" : "CPU Utilization", "color" : "#FF0000" }]
            ],
            "view" : "timeSeries",
            "stacked" : false,
            "region" : "eu-central-1",
            "title" : "CPU Utilization"
          }
        },
        {
          "type" : "metric",
          "x" : 0,
          "y" : 3,
          "width" : 12,
          "height" : 6,
          "properties" : {
            "metrics" : [
              ["AWS/EC2", "NetworkIn", "AutoScalingGroupName", "app-auto-scaling-group", { "label" : "Network In", "color" : "#FF0000" }]
            ],
            "view" : "timeSeries",
            "stacked" : false,
            "region" : "eu-central-1",
            "title" : "Network In"
          }
        },
        {
          "type" : "metric",
          "x" : 0,
          "y" : 3,
          "width" : 12,
          "height" : 6,
          "properties" : {
            "metrics" : [
              ["AWS/EC2", "NetworkOut", "AutoScalingGroupName", "app-auto-scaling-group", { "label" : "Network Out", "color" : "#FF0000" }]
            ],
            "view" : "timeSeries",
            "stacked" : false,
            "region" : "eu-central-1",
            "title" : "Network Out"
          }
        }
      ]
    }
  )
}
