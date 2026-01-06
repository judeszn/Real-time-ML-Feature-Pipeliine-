# VPC Outputs
output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

# EKS Outputs
output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_security_group_id" {
  description = "EKS cluster security group ID"
  value       = module.eks.cluster_security_group_id
}

output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

# MSK Outputs
output "msk_bootstrap_brokers" {
  description = "MSK bootstrap brokers"
  value       = module.msk.bootstrap_brokers
  sensitive   = true
}

output "msk_bootstrap_brokers_tls" {
  description = "MSK bootstrap brokers with TLS"
  value       = module.msk.bootstrap_brokers_tls
  sensitive   = true
}

output "msk_zookeeper_connect_string" {
  description = "MSK ZooKeeper connection string"
  value       = module.msk.zookeeper_connect_string
}

# RDS Outputs
output "rds_endpoint" {
  description = "RDS endpoint"
  value       = module.rds.endpoint
}

output "rds_port" {
  description = "RDS port"
  value       = module.rds.port
}

output "rds_database_name" {
  description = "RDS database name"
  value       = module.rds.database_name
}

# ElastiCache Outputs
output "redis_endpoint" {
  description = "Redis endpoint"
  value       = module.elasticache.endpoint
}

output "redis_port" {
  description = "Redis port"
  value       = module.elasticache.port
}

# ALB Outputs
output "alb_dns_name" {
  description = "ALB DNS name"
  value       = module.alb.dns_name
}

output "alb_zone_id" {
  description = "ALB zone ID for Route53"
  value       = module.alb.zone_id
}

# ECR Outputs
output "ecr_ingestion_repository_url" {
  description = "ECR repository URL for ingestion service"
  value       = aws_ecr_repository.ingestion_service.repository_url
}

output "ecr_processor_repository_url" {
  description = "ECR repository URL for feature processor"
  value       = aws_ecr_repository.feature_processor.repository_url
}

# S3 Outputs
output "s3_artifacts_bucket" {
  description = "S3 bucket for artifacts"
  value       = aws_s3_bucket.artifacts.bucket
}

output "s3_backups_bucket" {
  description = "S3 bucket for backups"
  value       = aws_s3_bucket.backups.bucket
}

# Secrets Manager Outputs
output "database_credentials_secret_arn" {
  description = "ARN of database credentials secret"
  value       = aws_secretsmanager_secret.database_credentials.arn
}

# CloudWatch Outputs
output "cloudwatch_log_groups" {
  description = "CloudWatch log groups"
  value = {
    ingestion_service  = aws_cloudwatch_log_group.ingestion_service.name
    feature_processor  = aws_cloudwatch_log_group.feature_processor.name
  }
}

# Quick Reference Output
output "deployment_info" {
  description = "Quick reference for deployment"
  value = <<-EOT
    
    ═══════════════════════════════════════════════════════════════
    🚀 AWS ML Feature Pipeline Deployment Information
    ═══════════════════════════════════════════════════════════════
    
    Environment: ${var.environment}
    Region: ${var.aws_region}
    
    📦 KUBERNETES
    Cluster: ${module.eks.cluster_name}
    Config:  aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}
    
    📨 KAFKA (MSK)
    Brokers: ${module.msk.bootstrap_brokers_tls}
    
    🗄️  DATABASE (RDS)
    Endpoint: ${module.rds.endpoint}
    Database: ${module.rds.database_name}
    Secret:   ${aws_secretsmanager_secret.database_credentials.name}
    
    ⚡ CACHE (ElastiCache)
    Endpoint: ${module.elasticache.endpoint}:${module.elasticache.port}
    
    🌐 LOAD BALANCER
    DNS: ${module.alb.dns_name}
    
    🐳 CONTAINER REGISTRIES
    Ingestion: ${aws_ecr_repository.ingestion_service.repository_url}
    Processor: ${aws_ecr_repository.feature_processor.repository_url}
    
    📊 MONITORING
    Logs: /aws/eks/${var.project_name}/
    
    ═══════════════════════════════════════════════════════════════
    
    Next Steps:
    1. Configure kubectl: Run the command above
    2. Deploy Helm charts: cd ../helm && helm install feature-pipeline ./feature-pipeline
    3. Verify deployment: kubectl get pods -n ml-pipeline
    
  EOT
}
