variable "environment" {
  description = "Environment name"
  type        = string
}

variable "cluster_id" {
  description = "ElastiCache cluster ID"
  type        = string
}

variable "redis_version" {
  description = "Redis version"
  type        = string
}

variable "node_type" {
  description = "Redis node type"
  type        = string
}

variable "num_cache_nodes" {
  description = "Number of cache nodes"
  type        = number
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for ElastiCache"
  type        = list(string)
}

variable "vpc_cidr" {
  description = "VPC CIDR block for security group rules"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
