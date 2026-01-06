# Development Environment Configuration
environment = "dev"
aws_region  = "us-east-1"

# VPC
vpc_cidr             = "10.0.0.0/16"
availability_zones   = ["us-east-1a", "us-east-1b"]
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.101.0/24", "10.0.102.0/24"]

# EKS - Smaller for dev
eks_cluster_version = "1.28"
eks_node_groups = {
  general = {
    desired_size   = 2
    min_size       = 1
    max_size       = 4
    instance_types = ["t3.medium"]
    capacity_type  = "ON_DEMAND"
  }
}

# MSK - Minimal config for dev
kafka_version        = "3.5.1"
kafka_broker_count   = 2
kafka_instance_type  = "kafka.t3.small"
kafka_storage_size   = 50

# RDS - Smaller instance for dev
postgres_version    = "15.4"
rds_instance_class  = "db.t3.micro"
rds_storage_size    = 50
database_name       = "features_dev"
db_username         = "dbadmin"

# ElastiCache - Single node for dev
redis_version    = "7.0"
redis_node_type  = "cache.t3.micro"
redis_node_count = 1

# Security
enable_waf = false

# Retention
backup_retention_days = 7
log_retention_days    = 7

# Tags
tags = {
  CostCenter = "Engineering"
  Owner      = "ML-Team"
  Purpose    = "Development"
}
