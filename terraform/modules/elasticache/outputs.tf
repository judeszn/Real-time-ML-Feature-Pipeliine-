output "cluster_id" {
  description = "ElastiCache cluster ID"
  value       = aws_elasticache_replication_group.main.id
}

output "endpoint" {
  description = "Primary endpoint address"
  value       = aws_elasticache_replication_group.main.primary_endpoint_address
}

output "port" {
  description = "Redis port"
  value       = aws_elasticache_replication_group.main.port
}

output "reader_endpoint" {
  description = "Reader endpoint address"
  value       = aws_elasticache_replication_group.main.reader_endpoint_address
}

output "security_group_id" {
  description = "ElastiCache security group ID"
  value       = aws_security_group.redis.id
}
