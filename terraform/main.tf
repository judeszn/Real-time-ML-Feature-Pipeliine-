terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "ml-feature-pipeline"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# VPC Module - Network foundation
module "vpc" {
  source = "./modules/vpc"

  environment          = var.environment
  vpc_cidr            = var.vpc_cidr
  availability_zones  = var.availability_zones
  public_subnet_cidrs = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  
  enable_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# EKS Module - Kubernetes cluster
module "eks" {
  source = "./modules/eks"

  environment        = var.environment
  cluster_name       = "${var.project_name}-${var.environment}"
  cluster_version    = var.eks_cluster_version
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  node_groups        = var.eks_node_groups

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# MSK Module - Managed Kafka
module "msk" {
  source = "./modules/msk"

  environment          = var.environment
  cluster_name         = "${var.project_name}-${var.environment}-kafka"
  kafka_version        = var.kafka_version
  broker_instance_type = var.kafka_instance_type
  broker_count         = var.kafka_broker_count
  broker_storage_size  = var.kafka_storage_size
  vpc_id               = module.vpc.vpc_id
  private_subnet_ids   = module.vpc.private_subnet_ids
  vpc_cidr             = module.vpc.vpc_cidr

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# RDS Module - PostgreSQL with TimescaleDB
module "rds" {
  source = "./modules/rds"

  environment             = var.environment
  identifier              = "${var.project_name}-${var.environment}-db"
  database_name           = var.database_name
  username                = var.db_username
  postgres_version        = var.postgres_version
  instance_class          = var.rds_instance_class
  allocated_storage       = var.rds_storage_size
  vpc_id                  = module.vpc.vpc_id
  private_subnet_ids      = module.vpc.private_subnet_ids
  vpc_cidr                = module.vpc.vpc_cidr
  backup_retention_period = var.backup_retention_days
  multi_az                = false

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# ElastiCache Module - Redis
module "elasticache" {
  source = "./modules/elasticache"

  environment        = var.environment
  cluster_id         = "${var.project_name}-${var.environment}-redis"
  redis_version      = var.redis_version
  node_type          = var.redis_node_type
  num_cache_nodes    = var.redis_node_count
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  vpc_cidr           = module.vpc.vpc_cidr

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}


