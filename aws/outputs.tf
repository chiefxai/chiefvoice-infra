output "backend_public_ip" { value = aws_eip.backend.public_ip }
output "backend_instance_id" { value = aws_instance.backend.id }
output "backend_url" { value = "https://${var.public_domain}" }
output "post_call_queue_url" { value = aws_sqs_queue.post_call.url }
output "post_call_dlq_url" { value = aws_sqs_queue.post_call_dlq.url }
output "object_storage_bucket" { value = aws_s3_bucket.objects.bucket }
