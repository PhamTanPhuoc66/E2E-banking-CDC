# Output private IP để biết đường SSH vào
output "kafka_private_ip" {
  value = aws_instance.kafka_host.private_ip
}


output "rds_source_endpoint" {
  value = aws_db_instance.source_db.endpoint
}

output "bastion_public_ip" {
  description = "Public IP address of the Bastion host"
  value       = aws_instance.bastion_host.public_ip
}
output "datalake_bucket_name" {
  description = "The exact name of the created S3 datalake bucket"
  value       = aws_s3_bucket.datalake_bucket.bucket
}