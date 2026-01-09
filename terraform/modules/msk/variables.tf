variable "environment" {
  description = "Environment name"
  type        = string
}

variable "cluster_name" {
  description = "MSK cluster name"
  type        = string
}

variable "kafka_version" {
  description = "Kafka version"
  type        = string
}

variable "broker_instance_type" {
  description = "Instance type for Kafka brokers"
  type        = string
}

variable "broker_count" {
  description = "Number of broker nodes"
  type        = number
}

variable "broker_storage_size" {
  description = "Storage size per broker in GB"
  type        = number
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for MSK brokers"
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
