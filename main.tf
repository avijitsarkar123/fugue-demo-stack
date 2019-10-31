provider "aws" {
  region = "${var.aws_region}"
}

data "aws_availability_zones" "available" {}

resource "aws_vpc" "demo-vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name         = "demo-vpc"
    Environment  = "dev"
    OwnerContact = "Avijit Sarkar"
  }
}

### Network Setup

# Create the private subnets
resource "aws_subnet" "private_subnets" {
  count             = "${var.az_count}"
  cidr_block        = "${cidrsubnet(aws_vpc.demo-vpc.cidr_block, 8, count.index)}"
  availability_zone = "${data.aws_availability_zones.available.names[count.index]}"
  vpc_id            = "${aws_vpc.demo-vpc.id}"

  tags = {
    Name         = "demo-vpc-private-subnets"
    Environment  = "dev"
    OwnerContact = "Avijit Sarkar"
  }
}

# Create the public subnets
resource "aws_subnet" "public_subnets" {
  count                   = "${var.az_count}"
  cidr_block              = "${cidrsubnet(aws_vpc.demo-vpc.cidr_block, 8, var.az_count + count.index)}"
  availability_zone       = "${data.aws_availability_zones.available.names[count.index]}"
  vpc_id                  = "${aws_vpc.demo-vpc.id}"
  map_public_ip_on_launch = true

  tags = {
    Name         = "demo-vpc-public-subnets"
    Environment  = "dev"
    OwnerContact = "Avijit Sarkar"
  }
}

# Create IGW for the public subnets
resource "aws_internet_gateway" "igw" {
  vpc_id = "${aws_vpc.demo-vpc.id}"

  tags = {
    Name         = "demo-vpc-igw"
    Environment  = "dev"
    OwnerContact = "Avijit Sarkar"
  }
}

# Route the public subnets traffic through the IGW
resource "aws_route" "internet_access" {
  route_table_id         = "${aws_vpc.demo-vpc.main_route_table_id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.igw.id}"
}

# Create a NAT gateway with an EIP for each private subnet to get internet access
resource "aws_eip" "eip" {
  count      = "${var.az_count}"
  vpc        = true
  depends_on = ["aws_internet_gateway.igw"]
}

resource "aws_nat_gateway" "natgw" {
  count         = "${var.az_count}"
  subnet_id     = "${element(aws_subnet.public_subnets.*.id, count.index)}"
  allocation_id = "${element(aws_eip.eip.*.id, count.index)}"

  tags = {
    Name         = "demo-vpc-natgw"
    Environment  = "dev"
    OwnerContact = "Avijit Sarkar"
  }
}

# Create a new route table for the private subnets
# Route non-local traffic to internet through NATGW
resource "aws_route_table" "private_subnets_rt" {
  count  = "${var.az_count}"
  vpc_id = "${aws_vpc.demo-vpc.id}"

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = "${element(aws_nat_gateway.natgw.*.id, count.index)}"
  }

  tags = {
    Name         = "demo-vpc-route-table"
    Environment  = "dev"
    OwnerContact = "Avijit Sarkar"
  }
}

resource "aws_route_table_association" "private_subnets_rt_assoc" {
  count          = "${var.az_count}"
  subnet_id      = "${element(aws_subnet.private_subnets.*.id, count.index)}"
  route_table_id = "${element(aws_route_table.private_subnets_rt.*.id, count.index)}"
}

### Security Group Setup

# ALB Security group
resource "aws_security_group" "lb-sg" {
  name        = "alb-sg"
  description = "controls access to the ALB"
  vpc_id      = "${aws_vpc.demo-vpc.id}"

  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name         = "demo-vpc-lb-sg"
    Environment  = "dev"
    OwnerContact = "Avijit Sarkar"
  }
}

# Traffic to the ECS Cluster should only come from the ALB
resource "aws_security_group" "app-sg" {
  name        = "ecs-tasks-sg"
  description = "allow inbound access from the ECS ALB only"
  vpc_id      = "${aws_vpc.demo-vpc.id}"

  ingress {
    protocol        = "tcp"
    from_port       = "8080"
    to_port         = "8099"
    security_groups = ["${aws_security_group.lb-sg.id}"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name         = "demo-vpc-app-sg"
    Environment  = "dev"
    OwnerContact = "Avijit Sarkar"
  }
}

### ALB

resource "aws_alb" "demo-app-alb" {
  name            = "demo-app-alb"
  subnets         = ["${aws_subnet.public_subnets.*.id}"]
  security_groups = ["${aws_security_group.lb-sg.id}"]

  tags = {
    Name         = "demo-app-alb"
    ASV          = "ASVTESTPLATFORM"
    Environment  = "dev"
    OwnerContact = "Avijit Sarkar"
  }
}

resource "aws_alb_target_group" "demo-app-tg" {
  name        = "demo-app-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = "${aws_vpc.demo-vpc.id}"
  target_type = "ip"

  health_check {
    path = "/health"
  }

  tags = {
    Name         = "demo-app-tg"
    ASV          = "ASVDEMOAPP"
    Environment  = "dev"
    OwnerContact = "Avijit Sarkar"
  }
}

# Redirect all traffic from the ALB to the target group
resource "aws_alb_listener" "demo-app-alb-listener" {
  load_balancer_arn = "${aws_alb.demo-app-alb.id}"
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = "${aws_alb_target_group.demo-app-tg.id}"
    type             = "forward"
  }
}

resource "aws_autoscaling_group" "demo-app-asg" {
  availability_zones   = ["${split(",", var.availability_zones)}"]
  name_prefix          = "demo-app-asg"
  max_size             = "${var.asg_max}"
  min_size             = "${var.asg_min}"
  desired_capacity     = "${var.asg_desired}"
  force_delete         = true
  launch_configuration = "${aws_launch_configuration.demo-app-lc.name}"
  vpc_zone_identifier  = ["${aws_subnet.private_subnets.*.id}"]

  lifecycle {
    create_before_destroy = true
  }

  #vpc_zone_identifier = ["${split(",", var.availability_zones)}"]
  tag {
    key                 = "Name"
    value               = "demo-app-asg"
    propagate_at_launch = "true"
  }

  tag {
    key                 = "OwnerContact"
    value               = "Avijit Sarkar"
    propagate_at_launch = "true"
  }

  tag {
    key                 = "ASV"
    value               = "ASVTESTPLATFORM"
    propagate_at_launch = "true"
  }

  tag {
    key                 = "Environment"
    value               = "dev"
    propagate_at_launch = "true"
  }
}

resource "aws_launch_configuration" "demo-app-lc" {
  name_prefix          = "terraform-example-lc"
  image_id             = "${lookup(var.aws_amis, var.aws_region)}"
  instance_type        = "${var.instance_type}"
  user_data            = "${data.template_file.user_data.rendered}"
  iam_instance_profile = "${aws_iam_instance_profile.demo-app-ec2-profile.name}"

  # Security group
  security_groups = ["${aws_security_group.app-sg.id}"]
  key_name        = "${var.key_name}"

  lifecycle {
    create_before_destroy = true
  }
}

### ECS

resource "aws_ecs_cluster" "sample-app-ecs-cluster" {
  name = "demo-ecs-cluster"
}

data "template_file" "user_data" {
  template = "${file("${path.module}/user_data.sh")}"

  vars {
    ecs_logging  = "${var.ecs_logging}"
    cluster_name = "${aws_ecs_cluster.sample-app-ecs-cluster.name}"
  }
}

resource "aws_ecs_task_definition" "sample-app-ecs-td" {
  family                = "sample-app"
  network_mode          = "awsvpc"
  task_role_arn         = "${aws_iam_role.demo-app-role.arn}"
  execution_role_arn    = "${aws_iam_role.demo-app-role.arn}"
  container_definitions = "${file("demo-app-td.json")}"

  tags = {
    Name         = "demo-app-ecs-task"
    ASV          = "ASVDEMOAPP"
    Environment  = "dev"
    OwnerContact = "Avijit Sarkar"
  }
}

resource "aws_ecs_service" "sample-app-ecs-service" {
  name                    = "sample-app-service"
  cluster                 = "${aws_ecs_cluster.sample-app-ecs-cluster.id}"
  task_definition         = "${aws_ecs_task_definition.sample-app-ecs-td.arn}"
  desired_count           = "${var.app_count}"
  launch_type             = "EC2"
  enable_ecs_managed_tags = true
  propagate_tags          = "TASK_DEFINITION"

  network_configuration {
    security_groups = ["${aws_security_group.app-sg.id}"]
    subnets         = ["${aws_subnet.private_subnets.*.id}"]
  }

  load_balancer {
    target_group_arn = "${aws_alb_target_group.demo-app-tg.id}"
    container_name   = "demo-app"
    container_port   = "${var.demo_app_port}"
  }

  tags = {
    Name         = "demo-app-ecs-service"
    ASV          = "ASVDEMOAPP"
    Environment  = "dev"
    OwnerContact = "Avijit Sarkar"
  }

  depends_on = [
    "aws_alb_listener.demo-app-alb-listener",
    "aws_cloudwatch_log_group.demo-app-ecs-log-group",
    "aws_cloudwatch_log_stream.demo-app-ecs-log-stream",
    "aws_iam_role_policy.demo-app-ecs-policy",
  ]
}
