terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ==============================================================================
# NETWORKING & SECURITY GROUPS
# ==============================================================================
data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "ecs_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.project_name}-ecs-vpc"
    Environment = var.environment
  }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.ecs_vpc.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-subnet-${count.index + 1}"
  }
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.ecs_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, count.index + 2)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.project_name}-private-subnet-${count.index + 1}"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.ecs_vpc.id
  tags   = { Name = "${var.project_name}-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.ecs_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "${var.project_name}-public-rt" }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${var.project_name}-nat-eip" }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  tags          = { Name = "${var.project_name}-nat" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.ecs_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = { Name = "${var.project_name}-private-rt" }
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ==============================================================================
# NETWORK LOAD BALANCER (NLB - LAYER 4 ULTRA-LOW LATENCY & COST OPTIMIZED)
# ==============================================================================
resource "aws_security_group" "nlb_sg" {
  name        = "${var.project_name}-nlb-sg"
  description = "Public TCP traffic to Layer-4 Network Load Balancer"
  vpc_id      = aws_vpc.ecs_vpc.id

  ingress {
    description = "Public HTTP entry"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Public HTTPS entry"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Direct Cosmo Router probe"
    from_port   = 8080
    to_port     = 8080
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

resource "aws_security_group" "ecs_sg" {
  name        = "${var.project_name}-ecs-tasks-sg"
  description = "Allow inbound from NLB and East-West between tasks"
  vpc_id      = aws_vpc.ecs_vpc.id

  ingress {
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.nlb_sg.id]
  }

  ingress {
    from_port = 0
    to_port   = 65535
    protocol  = "tcp"
    self      = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "main" {
  name                             = "${var.project_name}-nlb"
  internal                         = false
  load_balancer_type               = "network"
  security_groups                  = [aws_security_group.nlb_sg.id]
  subnets                          = aws_subnet.public[*].id
  enable_cross_zone_load_balancing = true

  tags = {
    Name        = "${var.project_name}-nlb"
    Environment = var.environment
    Layer       = "4-Transport"
  }
}

resource "aws_lb_target_group" "frontend" {
  name        = "${var.project_name}-frontend-tg"
  port        = 8080
  protocol    = "TCP"
  vpc_id      = aws_vpc.ecs_vpc.id
  target_type = "ip"

  health_check {
    protocol            = "TCP"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_target_group" "router" {
  name        = "${var.project_name}-router-tg"
  port        = 8080
  protocol    = "TCP"
  vpc_id      = aws_vpc.ecs_vpc.id
  target_type = "ip"

  health_check {
    protocol            = "TCP"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

# Port 80 forwards directly to Frontend (which handles SPA & reverse proxy to router)
resource "aws_lb_listener" "frontend_tcp" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

# Port 8080 forwards directly to Cosmo Router GraphQL Supergraph
resource "aws_lb_listener" "router_tcp" {
  load_balancer_arn = aws_lb.main.arn
  port              = 8080
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.router.arn
  }
}

# ==============================================================================
# ECS CLUSTER & SERVICE CONNECT
# ==============================================================================
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-ecs-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_service_discovery_http_namespace" "internal" {
  name        = "microservices.local"
  description = "ECS Service Connect discovery namespace"
}

# CloudWatch Logs
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = 7
}

# IAM Execution Role
resource "aws_iam_role" "ecs_execution" {
  name = "${var.project_name}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_base" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ==============================================================================
# CORE ECS SERVICES (COSMO ROUTER & FRONTEND)
# ==============================================================================
resource "aws_ecs_task_definition" "cosmo_router" {
  family                   = "cosmo-router"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution.arn

  container_definitions = jsonencode([{
    name      = "cosmo-router"
    image     = "${var.container_registry}/cosmo-router:latest"
    essential = true
    portMappings = [{
      containerPort = 8080
      name          = "router-http"
    }]
    environment = [
      { name = "LISTEN_ADDR", value = "0.0.0.0:8080" },
      { name = "LOG_LEVEL", value = "info" }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.ecs.name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "router"
      }
    }
  }])
}

resource "aws_ecs_service" "cosmo_router" {
  name            = "cosmo-router"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.cosmo_router.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.router.arn
    container_name   = "cosmo-router"
    container_port   = 8080
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.internal.arn
    service {
      port_name      = "router-http"
      discovery_name = "cosmo-router"
      client_alias {
        port = 8080
      }
    }
  }
}

resource "aws_ecs_task_definition" "frontend" {
  family                   = "frontend"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution.arn

  container_definitions = jsonencode([{
    name      = "frontend"
    image     = "${var.container_registry}/frontend:latest"
    essential = true
    portMappings = [{
      containerPort = 8080
      name          = "frontend-http"
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.ecs.name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "frontend"
      }
    }
  }])
}

resource "aws_ecs_service" "frontend" {
  name            = "frontend"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.frontend.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.frontend.arn
    container_name   = "frontend"
    container_port   = 8080
  }
}
