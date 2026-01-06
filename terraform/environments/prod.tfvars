# Production Environment Configuration
environment = "prod"
aws_region  = "us-east-1"

# VPC - Full HA with 3 AZs
vpc_cidr             = "10.0.0.0/16"
availability_zones   = ["us-east-1a", "us-east-1b", "us-east-1c"]
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
private_subnet_cidrs = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

# EKS - Production ready
eks_cluster_version = "1.28"
eks_node_groups = {
  general = {
    desired_size   = 6
    min_size       = 3
    max_size       = 20
    instance_types = ["t3.large"]
    capacity_type  = "ON_DEMAND"
  }
  spot = {
    desired_size   = 3
    min_size       = 0
    max_size       = 10
    instance_types = ["t3.large", "t3a.large"]
    capacity_type  = "SPOT"
  }
}

# MSK - Production grade
kafka_version        = "3.5.1"
kafka_broker_count   = 3
kafka_instance_type  = "kafka.m5.large"
kafka_storage_size   = 500

# RDS - High availability
postgres_version    = "15.4"
rds_instance_class  = "db.r5.xlarge"
rds_storage_size    = 500
database_name       = "features_prod"
db_username         = "dbadmin"

# ElastiCache - Multi-AZ cluster
redis_version    = "7.0"
redis_node_type  = "cache.r5.large"
redis_node_count = 3

# Security
enable_waf = true
# Set acm_certificate_arn after creating ACM certificate

# Retention
backup_retention_days = 30
log_retention_days    = 90

# Tags
tags = {
  CostCenter = "Engineering"
  Owner      = "ML-Team"
  Purpose    = "Production"
  Compliance = "SOC2"
}
