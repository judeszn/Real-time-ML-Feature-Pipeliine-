terraform {
  required_version = ">= 1.6"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }

  backend "s3" {
    bucket         = "ml-feature-pipeline-terraform-state"
    key            = "terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
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

# Data source for EKS cluster
data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_name
  depends_on = [module.eks]
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_name
  depends_on = [module.eks]
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

# VPC Module
module "vpc" {
  source = "./modules/vpc"

  environment         = var.environment
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  
  enable_nat_gateway = true
  enable_dns_hostnames = true
  enable_dns_support   = true
}

# EKS Module
module "eks" {
  source = "./modules/eks"

  environment    = var.environment
  cluster_name   = "${var.project_name}-${var.environment}"
  cluster_version = var.eks_cluster_version

  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnet_ids
  
  node_groups = var.eks_node_groups
  
  enable_irsa = true
  enable_cluster_autoscaler = true
}

# MSK (Managed Kafka) Module
module "msk" {
  source = "./modules/msk"

  environment     = var.environment
  cluster_name    = "${var.project_name}-kafka-${var.environment}"
  kafka_version   = var.kafka_version
  
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnet_ids
  
  number_of_broker_nodes = var.kafka_broker_count
  broker_instance_type   = var.kafka_instance_type
  broker_storage_size    = var.kafka_storage_size
  
  encryption_in_transit = true
  enhanced_monitoring   = "PER_TOPIC_PER_BROKER"
}

# RDS PostgreSQL Module
module "rds" {
  source = "./modules/rds"

  environment       = var.environment
  identifier        = "${var.project_name}-db-${var.environment}"
  
  engine            = "postgres"
  engine_version    = var.postgres_version
  instance_class    = var.rds_instance_class
  allocated_storage = var.rds_storage_size
  
  database_name     = var.database_name
  master_username   = var.db_username
  
  vpc_id            = module.vpc.vpc_id
  subnet_ids        = module.vpc.private_subnet_ids
  
  multi_az          = var.environment == "prod" ? true : false
  backup_retention_period = var.environment == "prod" ? 7 : 3
  
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  auto_minor_version_upgrade     = true
  
  # TimescaleDB extension will be enabled via init script
  parameter_group_family = "postgres15"
  parameters = [
    {
      name  = "shared_preload_libraries"
      value = "timescaledb"
    }
  ]
}

# ElastiCache Redis Module
module "elasticache" {
  source = "./modules/elasticache"

  environment     = var.environment
  cluster_id      = "${var.project_name}-redis-${var.environment}"
  
  engine_version  = var.redis_version
  node_type       = var.redis_node_type
  num_cache_nodes = var.redis_node_count
  
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnet_ids
  
  parameter_group_name = "default.redis7"
  port                = 6379
  
  automatic_failover_enabled = var.environment == "prod" ? true : false
  multi_az_enabled          = var.environment == "prod" ? true : false
}

# Application Load Balancer Module
module "alb" {
  source = "./modules/alb"

  environment = var.environment
  name        = "${var.project_name}-alb-${var.environment}"
  
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnet_ids
  
  enable_deletion_protection = var.environment == "prod" ? true : false
  enable_http2              = true
  enable_waf                = var.enable_waf
  
  certificate_arn = var.acm_certificate_arn
}

# ECR Repositories
resource "aws_ecr_repository" "ingestion_service" {
  name                 = "${var.project_name}/ingestion-service"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_repository" "feature_processor" {
  name                 = "${var.project_name}/feature-processor"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

# S3 Buckets
resource "aws_s3_bucket" "artifacts" {
  bucket = "${var.project_name}-artifacts-${var.environment}-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket" "backups" {
  bucket = "${var.project_name}-backups-${var.environment}-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    id     = "delete-old-backups"
    status = "Enabled"

    expiration {
      days = var.backup_retention_days
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }
  }
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "ingestion_service" {
  name              = "/aws/eks/${var.project_name}/ingestion-service"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "feature_processor" {
  name              = "/aws/eks/${var.project_name}/feature-processor"
  retention_in_days = var.log_retention_days
}

# Secrets Manager
resource "aws_secretsmanager_secret" "database_credentials" {
  name = "${var.project_name}/database-credentials-${var.environment}"
  description = "Database credentials for ML Feature Pipeline"
}

resource "aws_secretsmanager_secret_version" "database_credentials" {
  secret_id = aws_secretsmanager_secret.database_credentials.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db_password.result
    host     = module.rds.endpoint
    port     = module.rds.port
    database = var.database_name
  })
}

resource "random_password" "db_password" {
  length  = 32
  special = true
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
