terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ── VPC (shared across compute types) ─────────────────────────────────────────
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name             = "${var.environment}-vpc"
  cidr             = var.vpc_cidr
  azs              = var.availability_zones
  private_subnets  = var.private_subnet_cidrs
  public_subnets   = var.public_subnet_cidrs
  enable_nat_gateway = true
  single_nat_gateway = var.environment != "prod"

  tags = local.common_tags
}

locals {
  common_tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
    Project     = "okta-cicd-assessment"
  }
}

# ────────────────────────────────────────────────────────────────────────────────
# EC2 PATH
# ────────────────────────────────────────────────────────────────────────────────
resource "aws_security_group" "ec2" {
  count       = var.compute_type == "ec2" ? 1 : 0
  name        = "${var.environment}-ec2-sg"
  description = "EC2 instance security group"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "HTTPS from VPC only"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = local.common_tags
}

resource "aws_instance" "app" {
  count                  = var.compute_type == "ec2" ? var.ec2_instance_count : 0
  ami                    = var.ec2_ami_id
  instance_type          = var.ec2_instance_type
  subnet_id              = module.vpc.private_subnets[count.index % length(module.vpc.private_subnets)]
  vpc_security_group_ids = [aws_security_group.ec2[0].id]
  iam_instance_profile   = aws_iam_instance_profile.ec2[0].name

  metadata_options {
    http_tokens = "required"   # IMDSv2 only — security best practice
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = var.ec2_volume_size_gb
    encrypted   = true
  }

  tags = merge(local.common_tags, { Name = "${var.environment}-app-${count.index}" })
}

resource "aws_iam_role" "ec2" {
  count = var.compute_type == "ec2" ? 1 : 0
  name  = "${var.environment}-ec2-role"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  count      = var.compute_type == "ec2" ? 1 : 0
  role       = aws_iam_role.ec2[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2" {
  count = var.compute_type == "ec2" ? 1 : 0
  name  = "${var.environment}-ec2-profile"
  role  = aws_iam_role.ec2[0].name
}

# ────────────────────────────────────────────────────────────────────────────────
# ECS PATH
# ────────────────────────────────────────────────────────────────────────────────
resource "aws_ecs_cluster" "main" {
  count = var.compute_type == "ecs" ? 1 : 0
  name  = "${var.environment}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
  tags = local.common_tags
}

resource "aws_ecs_cluster_capacity_providers" "fargate" {
  count              = var.compute_type == "ecs" ? 1 : 0
  cluster_name       = aws_ecs_cluster.main[0].name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = var.environment == "prod" ? "FARGATE" : "FARGATE_SPOT"
    weight            = 1
  }
}

resource "aws_ecs_task_definition" "app" {
  count                    = var.compute_type == "ecs" ? 1 : 0
  family                   = "${var.environment}-app"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.ecs_task_cpu
  memory                   = var.ecs_task_memory
  execution_role_arn       = aws_iam_role.ecs_execution[0].arn
  task_role_arn            = aws_iam_role.ecs_task[0].arn

  container_definitions = jsonencode([{
    name      = "app"
    image     = var.ecs_container_image
    essential = true
    portMappings = [{
      containerPort = var.ecs_container_port
      protocol      = "tcp"
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/${var.environment}-app"
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "app"
      }
    }
    environment = [
      { name = "ENVIRONMENT", value = var.environment }
    ]
  }])
  tags = local.common_tags
}

resource "aws_ecs_service" "app" {
  count           = var.compute_type == "ecs" ? 1 : 0
  name            = "${var.environment}-app"
  cluster         = aws_ecs_cluster.main[0].id
  task_definition = aws_ecs_task_definition.app[0].arn
  desired_count   = var.ecs_desired_count

  network_configuration {
    subnets          = module.vpc.private_subnets
    security_groups  = [aws_security_group.ecs[0].id]
    assign_public_ip = false
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
  tags = local.common_tags
}

resource "aws_security_group" "ecs" {
  count       = var.compute_type == "ecs" ? 1 : 0
  name        = "${var.environment}-ecs-sg"
  vpc_id      = module.vpc.vpc_id
  description = "ECS task security group"

  ingress {
    from_port   = var.ecs_container_port
    to_port     = var.ecs_container_port
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = local.common_tags
}

resource "aws_iam_role" "ecs_execution" {
  count = var.compute_type == "ecs" ? 1 : 0
  name  = "${var.environment}-ecs-execution-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ecs-tasks.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  count      = var.compute_type == "ecs" ? 1 : 0
  role       = aws_iam_role.ecs_execution[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task" {
  count = var.compute_type == "ecs" ? 1 : 0
  name  = "${var.environment}-ecs-task-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ecs-tasks.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

# ────────────────────────────────────────────────────────────────────────────────
# EKS PATH
# ────────────────────────────────────────────────────────────────────────────────
module "eks" {
  count   = var.compute_type == "eks" ? 1 : 0
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "${var.environment}-cluster"
  cluster_version = var.eks_cluster_version
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnets

  cluster_endpoint_public_access = false  # Private endpoint only

  eks_managed_node_groups = {
    default = {
      min_size       = var.eks_node_min
      max_size       = var.eks_node_max
      desired_size   = var.eks_node_desired
      instance_types = [var.eks_node_instance_type]
    }
  }

  tags = local.common_tags
}
