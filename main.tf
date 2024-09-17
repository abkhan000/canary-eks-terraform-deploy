terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.10.0"
    }
  }
}

provider "aws" {
  region = "ap-south-1"  # AWS region is already defined here
}

# Fetch details of the EKS cluster
data "aws_eks_cluster" "my_cluster" {
  name = local.cluster_name
}

data "aws_eks_cluster_auth" "my_cluster" {
  name = data.aws_eks_cluster.my_cluster.name
}

# Kubernetes provider configuration
provider "kubernetes" {
  host                   = data.aws_eks_cluster.my_cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.my_cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.my_cluster.token
}

# Get available AWS Availability Zones
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  cluster_name       = "K8S-cluster"
  availability_zones = slice(data.aws_availability_zones.available.names, 0, 3)  # Take first 3 AZs
}

# VPC module configuration
module "vpc" {
  source               = "terraform-aws-modules/vpc/aws"
  version              = "2.58.0"
  name                 = "kas-vpc"
  cidr                 = "172.16.0.0/16"
  azs                  = local.availability_zones
  private_subnets      = ["172.16.1.0/24", "172.16.2.0/24", "172.16.3.0/24"]
  public_subnets       = ["172.16.4.0/24", "172.16.5.0/24", "172.16.6.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"            = "1"
  }

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                     = "1"
  }
}

# EKS module configuration
module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "18.30.0"
  cluster_name    = local.cluster_name
  cluster_version = "1.27"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnets  # Reference the private subnets from the VPC module

  # Define EKS managed node groups
  eks_managed_node_groups = {
    first = {
      desired_capacity = 1
      max_capacity     = 10
      min_capacity     = 1
      instance_type    = "t2.micro"
    }
  }
}

# Optional: Output resources for debugging or future use
output "vpc_id" {
  value = module.vpc.vpc_id
}

output "private_subnets" {
  value = module.vpc.private_subnets
}

output "public_subnets" {
  value = module.vpc.public_subnets
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  value = data.aws_eks_cluster.my_cluster.endpoint
}

output "eks_cluster_version" {
  value = module.eks.cluster_version
}
