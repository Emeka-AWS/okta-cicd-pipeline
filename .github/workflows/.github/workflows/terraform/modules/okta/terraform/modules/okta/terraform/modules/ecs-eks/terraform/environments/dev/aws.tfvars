# terraform/environments/dev/aws.tfvars
# Dev environment — uses Fargate Spot and smaller instances to reduce cost

aws_region           = "us-east-1"
environment          = "dev"
compute_type         = "ec2"   # override via workflow input: ec2 | ecs | eks

vpc_cidr             = "10.10.0.0/16"
availability_zones   = ["us-east-1a", "us-east-1b"]
private_subnet_cidrs = ["10.10.1.0/24", "10.10.2.0/24"]
public_subnet_cidrs  = ["10.10.101.0/24", "10.10.102.0/24"]

# EC2
ec2_instance_type  = "t3.medium"
ec2_instance_count = 1
ec2_volume_size_gb = 20

# ECS
ecs_task_cpu         = 256
ecs_task_memory      = 512
ecs_desired_count    = 1
ecs_container_image  = "nginx:latest"   # replace with your image
ecs_container_port   = 8080

# EKS
eks_cluster_version    = "1.29"
eks_node_instance_type = "t3.medium"
eks_node_min           = 1
eks_node_max           = 3
eks_node_desired       = 1
