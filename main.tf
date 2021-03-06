terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.8"
    }
  }
}

provider "aws" {
  profile = "default"
  region  = "eu-west-2"
}

#resource "aws_instance" "example" {
#  ami           = "ami-0a669382ea0feb73a"
#  instance_type = "t2.micro"
#  key_name = "keyPair1"
#  security_groups = ["webServerGroup_eu-west-2"]
#}

resource "aws_vpc" "mainVpc" {
    cidr_block = "192.168.0.0/16"
    enable_dns_hostnames = true

    tags = {
        Name = "mainVpc"
    }
}

resource "aws_internet_gateway" "default" {
    vpc_id = aws_vpc.mainVpc.id
}

resource "aws_route_table" "mainRouteTable" {
    vpc_id = aws_vpc.mainVpc.id
    
    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.default.id
    }
    
    tags = {
        Name = "mainRouteTable"
    }
}

resource "aws_main_route_table_association" "routeTableAssoc" {
    vpc_id = aws_vpc.mainVpc.id
    route_table_id = aws_route_table.mainRouteTable.id

}

resource "aws_subnet" "eu-west-2a-public" {
    vpc_id = aws_vpc.mainVpc.id
    cidr_block = "192.168.1.0/24"
    availability_zone = "eu-west-2a"
    map_public_ip_on_launch = true
    tags = {
        Name = "Public Subnet-2a"
    }
}

resource "aws_subnet" "eu-west-2b-public" {
    vpc_id = aws_vpc.mainVpc.id
    cidr_block = "192.168.2.0/24"
    availability_zone = "eu-west-2b"
    map_public_ip_on_launch = true
    tags = {
        Name = "Public Subnet-2b"
    }
}

resource "aws_network_acl" "mainVpcNacl" {
    vpc_id = aws_vpc.mainVpc.id
    subnet_ids = [aws_subnet.eu-west-2a-public.id,aws_subnet.eu-west-2b-public.id]

    ingress {
        rule_no = 10
        protocol = "tcp"
        action = "allow"
        from_port = 80
        to_port = 80
        cidr_block = "86.5.167.59/32"
    }

    ingress {
        rule_no = 20
        protocol = "tcp"
        action = "allow"
        from_port = 443
        to_port = 443
        cidr_block = "86.5.167.59/32"
    }

    ingress {
        rule_no = 30
        protocol = "tcp"
        action = "allow"
        from_port = 22
        to_port = 22
        cidr_block = "86.5.167.59/32"
    }

    egress {
        rule_no = 10
        protocol = "tcp"
        action = "allow"
        from_port = 80
        to_port = 80
        cidr_block = "0.0.0.0/0"
    }

    egress {
        rule_no = 20
        protocol = "tcp"
        action = "allow"
        from_port = 443
        to_port = 443
        cidr_block = "0.0.0.0/0"
    }

    egress {
        rule_no = 30
        protocol = "tcp"
        action = "allow"
        from_port = 22
        to_port = 22
        cidr_block = "0.0.0.0/0"
    }

    egress {
        rule_no = 40
        protocol = "tcp"
        action = "allow"
        from_port = 1024
        to_port = 65535
        cidr_block = "0.0.0.0/0"        
    }

    tags = {
        Name = "mainVpcNacl"
    }
}

resource "aws_security_group" "publicSecurityGroup1" {
    name = "publicSecurityGroup1"
    vpc_id = aws_vpc.mainVpc.id
    tags = {
        Name = "publicSecurityGroup1"
    }

    ingress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port = 443
        to_port = 443
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["86.5.167.59/32"]
    }

    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
  }

}

resource "aws_lb_target_group" "asg1TargetGroup" {
    name = "asg1TargetGroup"
    port = 80
    protocol = "HTTP"
    vpc_id = aws_vpc.mainVpc.id
}

resource "aws_lb" "appLb1" {
    name = "appLb1"
    internal = "false"
    load_balancer_type = "application"
    security_groups = [aws_security_group.publicSecurityGroup1.id]
    subnets = [aws_subnet.eu-west-2a-public.id,aws_subnet.eu-west-2b-public.id]
}

resource "aws_lb_listener" "appLb1FrontEnd" {
    load_balancer_arn = aws_lb.appLb1.arn
    port = "80"
    protocol = "HTTP"

    default_action {
        type = "forward"
        target_group_arn = aws_lb_target_group.asg1TargetGroup.arn
    }
}

resource "aws_launch_template" "webServerTemplate2" {
    name = "webServerTemplate2"
    image_id = "ami-08ae9241eb68391ba"
    instance_type = "t2.micro"
    key_name = "keyPair1"
    vpc_security_group_ids = [aws_security_group.publicSecurityGroup1.id]

    #network_interfaces {
    #    associate_public_ip_address = true
    #}
}

resource "aws_placement_group" "pg1" {
    name = "pg1"
    strategy = "spread"
}

resource "aws_autoscaling_group" "asg1" {
    name ="asg1"
    max_size = 2
    min_size = 1
    desired_capacity = 2
    health_check_grace_period = 300
    health_check_type = "ELB"
    force_delete = true
    placement_group = aws_placement_group.pg1.id
    vpc_zone_identifier = [aws_subnet.eu-west-2a-public.id,aws_subnet.eu-west-2b-public.id]
    target_group_arns = [aws_lb_target_group.asg1TargetGroup.arn]

    launch_template {
        id = aws_launch_template.webServerTemplate2.id 
        version = "$Latest"
    }

    lifecycle {
        ignore_changes = [load_balancers, target_group_arns]
    }
}

#resource "aws_autoscaling_attachment" "asg1AttachAppLb1" {
#    autoscaling_group_name = "aws_autoscaling_group.asg1.id"
#    alb_target_group_arn = "aws_lb_target_group.asg1TargetGroup.arn"
#}