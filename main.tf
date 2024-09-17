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
  region     = "ap-south-1"
}

data "aws_eks_cluster" "my_cluster" {
  name = "my-eks-cluster"
}

data "aws_eks_cluster_auth" "my_cluster" {
  name = data.aws_eks_cluster.my_cluster.name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.my_cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.my_cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.my_cluster.token
  # Removed the load_config_file argument
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  region             = "ap-south-1"
  cluster_name       = "K8s-cluster"
  availability_zones = slice(data.aws_availability_zones.available.names, 0, 3)
}

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

resource "aws_cloudwatch_log_group" "eks_cluster" {
  name              = "/aws/eks/${local.cluster_name}/cluster"
  retention_in_days = 7
}

resource "aws_kms_key" "eks_logging" {
  description = "KMS key for EKS cluster logging"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "logs.ap-south-1.amazonaws.com"
        }
        Action = [
          "kms:Encrypt*",
          "kms:Decrypt*",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*"
        ]
        Resource = "*"
      },
    ]
  })
}
module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "20.24.0"
  cluster_name    = local.cluster_name
  cluster_version = "1.27"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnets

  eks_managed_node_groups = {
    first = {
      desired_capacity = 1
      max_capacity     = 10
      min_capacity     = 1
      instance_type    = "t2.micro"
    }
  }
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "private_subnets" {
  value = module.vpc.private_subnets
}

output "public_subnets" {
  value = module.vpc.public_subnets
}

output "eks_cluster_id" {
  description = "The name/id of the EKS cluster"
  value       = module.eks.cluster_id
}

output "eks_cluster_arn" {
  description = "The Amazon Resource Name (ARN) of the cluster"
  value       = module.eks.cluster_arn
}

output "eks_cluster_endpoint" {
  description = "Endpoint for your Kubernetes API server"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = module.eks.cluster_certificate_authority_data
}

output "eks_cluster_id" {
  description = "EKS cluster ID"
  value       = module.eks.cluster_id
}

output "eks_cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}
