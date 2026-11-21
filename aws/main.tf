locals { name = "chiefvoice" }

data "aws_availability_zones" "available" { state = "available" }
resource "aws_vpc" "main" {
  cidr_block = "10.42.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true
  tags = var.tags
}
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = var.tags
}
resource "aws_subnet" "public" {
  vpc_id = aws_vpc.main.id
  cidr_block = "10.42.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags = var.tags
}
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = var.tags
}
resource "aws_route_table_association" "public" {
  subnet_id = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}
resource "aws_subnet" "private" {
  vpc_id = aws_vpc.main.id
  cidr_block = "10.42.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = var.tags
}
resource "aws_eip" "nat" {
  domain = "vpc"
  tags = var.tags
}
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id = aws_subnet.public.id
  depends_on = [aws_internet_gateway.main]
  tags = var.tags
}
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
  tags = var.tags
}
resource "aws_route_table_association" "private" {
  subnet_id = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}
resource "aws_security_group" "lambda" {
  name = "${local.name}-lambda"
  vpc_id = aws_vpc.main.id
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = var.tags
}
resource "aws_security_group" "vm" {
  name = "${local.name}-vm"
  vpc_id = aws_vpc.main.id
  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = [var.ssh_allowed_cidr]
  }
  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 5432
    to_port = 5432
    protocol = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = var.tags
}

resource "random_password" "database" {
  length = 40
  special = false
}
resource "random_bytes" "app_keys" {
  for_each = toset(["credentials", "post-call", "recordings", "backup"])
  length = 32
}
resource "random_password" "vobiz_secrets" {
  for_each = toset(["webhook", "route-token"])
  length = 48
  special = false
}
locals {
  runtime_secret_values = {
    database      = random_password.database.result
    credentials   = random_bytes.app_keys["credentials"].base64
    post-call     = random_bytes.app_keys["post-call"].base64
    recordings    = random_bytes.app_keys["recordings"].base64
    backup        = random_bytes.app_keys["backup"].base64
    vobiz-webhook = random_password.vobiz_secrets["webhook"].result
    vobiz-route   = random_password.vobiz_secrets["route-token"].result
  }
}
resource "aws_secretsmanager_secret" "runtime" {
  for_each = toset(["database", "credentials", "post-call", "recordings", "backup", "vobiz-webhook", "vobiz-route"])
  name = "${local.name}/${each.key}"
  tags = var.tags
}
resource "aws_secretsmanager_secret_version" "runtime" {
  for_each = toset(["database", "credentials", "post-call", "recordings", "backup", "vobiz-webhook", "vobiz-route"])
  secret_id = aws_secretsmanager_secret.runtime[each.key].id
  secret_string = local.runtime_secret_values[each.key]
}
resource "aws_secretsmanager_secret" "lambda_database_url" {
  name = "${local.name}/lambda-database-url"
  tags = var.tags
}
resource "aws_secretsmanager_secret_version" "lambda_database_url" {
  secret_id = aws_secretsmanager_secret.lambda_database_url.id
  secret_string = "postgresql+asyncpg://${var.database_username}:${urlencode(random_password.database.result)}@${aws_instance.backend.private_ip}:5432/${var.database_name}"
}
resource "aws_s3_bucket" "objects" {
  bucket = var.object_storage_bucket_name
  force_destroy = false
  tags = var.tags
}
resource "aws_s3_bucket_public_access_block" "objects" {
  bucket = aws_s3_bucket.objects.id
  block_public_acls = true
  block_public_policy = true
  ignore_public_acls = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_server_side_encryption_configuration" "objects" {
  bucket = aws_s3_bucket.objects.id
  rule { apply_server_side_encryption_by_default { sse_algorithm = "AES256" } }
}
resource "aws_sqs_queue" "post_call_dlq" { name = "${local.name}-post-call-dlq"
  message_retention_seconds = 1209600
}
resource "aws_sqs_queue" "post_call" {
  name = "${local.name}-post-call"
  visibility_timeout_seconds = 1860
  message_retention_seconds = 345600
  receive_wait_time_seconds = 20
  redrive_policy = jsonencode({ deadLetterTargetArn = aws_sqs_queue.post_call_dlq.arn, maxReceiveCount = 5 })
}
resource "aws_iam_role" "lambda" {
  name = "${local.name}-post-call"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole" }] })
}
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  role = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}
resource "aws_lambda_function" "post_call" {
  function_name = "${local.name}-post-call"
  package_type = "Image"
  image_uri = var.post_call_lambda_image_uri
  role = aws_iam_role.lambda.arn
  architectures = ["arm64"]
  timeout = 300
  memory_size = 1024
  vpc_config {
    subnet_ids = [aws_subnet.private.id]
    security_group_ids = [aws_security_group.lambda.id]
  }
  environment {
    variables = {
    DATABASE_URL_SECRET_ARN = aws_secretsmanager_secret.lambda_database_url.arn
    POST_CALL_ENCRYPTION_KEY_SECRET_ARN = aws_secretsmanager_secret.runtime["post-call"].arn
    POST_CALL_AGENT_PROVIDER = "langchain_vertex"
    VERTEX_PROJECT_ISOLATION_ENABLED = "true"
    VERTEX_LOCATION = var.vertex_location
    POST_CALL_MODEL = var.post_call_model
    POST_CALL_LOCATION = var.post_call_location
    GOOGLE_CREDENTIALS_SECRET_ARN = var.google_credentials_secret_arn
  } }
  depends_on = [aws_secretsmanager_secret_version.lambda_database_url]
}
resource "aws_lambda_event_source_mapping" "post_call" {
  event_source_arn = aws_sqs_queue.post_call.arn
  function_name = aws_lambda_function.post_call.arn
  batch_size = 1
  function_response_types = ["ReportBatchItemFailures"]
}
resource "aws_iam_role_policy" "lambda_sqs" {
  role = aws_iam_role.lambda.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"], Resource = [aws_sqs_queue.post_call.arn] },
    { Effect = "Allow", Action = ["secretsmanager:GetSecretValue"], Resource = concat([var.google_credentials_secret_arn, aws_secretsmanager_secret.lambda_database_url.arn], [for secret in aws_secretsmanager_secret.runtime : secret.arn]) }
  ] })
}

resource "aws_iam_role" "vm" {
  name = "${local.name}-vm"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }] })
}
resource "aws_iam_role_policy_attachment" "vm_ssm" {
  role = aws_iam_role.vm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_role_policy_attachment" "vm_ecr_read" {
  role = aws_iam_role.vm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}
resource "aws_iam_role_policy" "vm_runtime" {
  role = aws_iam_role.vm.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["s3:ListBucket"], Resource = [aws_s3_bucket.objects.arn] },
    { Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"], Resource = ["${aws_s3_bucket.objects.arn}/*"] },
    { Effect = "Allow", Action = ["sqs:SendMessage"], Resource = [aws_sqs_queue.post_call.arn] },
    { Effect = "Allow", Action = ["secretsmanager:GetSecretValue"], Resource = concat([var.google_credentials_secret_arn], [for secret in aws_secretsmanager_secret.runtime : secret.arn]) }
  ] })
}
resource "aws_iam_instance_profile" "vm" {
  name = "${local.name}-vm"
  role = aws_iam_role.vm.name
}
resource "aws_instance" "backend" {
  ami = var.vm_ami_id
  instance_type = var.vm_instance_type
  subnet_id = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.vm.id]
  iam_instance_profile = aws_iam_instance_profile.vm.name
  key_name = var.ssh_key_name
  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    api_image_uri = var.api_image_uri
    api_registry = split("/", var.api_image_uri)[0]
    secret_arns = { for key, secret in aws_secretsmanager_secret.runtime : key => secret.arn }
    database_name = var.database_name
    database_username = var.database_username
    object_bucket = aws_s3_bucket.objects.bucket
    queue_url = aws_sqs_queue.post_call.url
    aws_region = var.aws_region
    public_domain = var.public_domain
    oidc_issuer = var.oidc_issuer
    oidc_audience = var.oidc_audience
    oidc_jwks_url = var.oidc_jwks_url
    platform_admin_subjects = join(",", var.platform_admin_subjects)
    vertex_location = var.vertex_location
    vertex_model = var.vertex_model
    post_call_model = var.post_call_model
    post_call_location = var.post_call_location
    gcp_project_parent = var.gcp_project_parent
    gcp_billing_account_id = trimprefix(var.gcp_billing_account_id, "billingAccounts/")
    gcp_runtime_service_account = var.gcp_runtime_service_account
    gcp_budget_api_project_id = var.gcp_budget_api_project_id
    gcp_vertex_monthly_spend_cap = var.gcp_vertex_monthly_spend_cap
    google_credentials_secret_arn = var.google_credentials_secret_arn
    recordings_enabled = var.recordings_enabled
  })
  root_block_device {
    volume_size = var.vm_disk_gb
    volume_type = "gp3"
    encrypted = true
  }
  tags = merge(var.tags, { Name = "${local.name}-backend" })
  depends_on = [aws_iam_role_policy.vm_runtime, aws_iam_role_policy_attachment.vm_ecr_read, aws_secretsmanager_secret_version.runtime]
}
resource "aws_eip" "backend" {
  domain = "vpc"
  tags = var.tags
}
resource "aws_eip_association" "backend" {
  instance_id = aws_instance.backend.id
  allocation_id = aws_eip.backend.id
}
