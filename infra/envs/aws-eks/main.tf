# PoC ASR1 en AWS: red + EKS + ECR + SQS/DLQ/DynamoDB/Lambda + permisos por pod (IRSA).
# Nada de esto se aplica sin confirmación explícita (plan 0002). Destruir todo: ../../../scripts/aws-down.sh

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  ms_group = {
    ami_type       = var.ami_type
    instance_types = [var.ms_instance_type]
    min_size       = var.ms_min_nodes
    max_size       = var.ms_max_nodes
    desired_size   = var.ms_min_nodes
    labels         = { role = "ms" }
    tags = { # descubrimiento del Cluster Autoscaler
      "k8s.io/cluster-autoscaler/enabled"     = "true"
      "k8s.io/cluster-autoscaler/${var.name}" = "owned"
    }
  }
  load_group = {
    ami_type       = var.ami_type
    instance_types = [var.load_instance_type]
    min_size       = 1
    max_size       = 1
    desired_size   = 1
    labels         = { role = "load" }
    taints = {
      load = { key = "load", value = "true", effect = "NO_SCHEDULE" }
    }
  }
}

# --- Red: solo subredes públicas (sin NAT Gateway: ahorra ~US$32/mes y es irrelevante para una sesión corta) ---
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.21.0"

  name = var.name
  cidr = "10.20.0.0/16"
  azs  = local.azs

  public_subnets          = ["10.20.0.0/24", "10.20.1.0/24"]
  map_public_ip_on_launch = true
  enable_nat_gateway      = false
  enable_dns_hostnames    = true

  # Etiquetas que usa Kubernetes para ubicar balanceadores (interno y público).
  public_subnet_tags = {
    "kubernetes.io/role/elb"          = 1
    "kubernetes.io/role/internal-elb" = 1
  }
}

# --- Clúster EKS con dos grupos de nodos: MS (autoescalable) y generador de carga (aparte, con taint) ---
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.37.2"

  cluster_name    = var.name
  cluster_version = var.cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnets

  cluster_endpoint_public_access           = true # se opera desde el equipo local con el perfil SSO
  enable_cluster_creator_admin_permissions = true
  enable_irsa                              = true

  cluster_addons = {
    coredns    = { most_recent = true }
    kube-proxy = { most_recent = true }
    vpc-cni    = { most_recent = true }
  }

  eks_managed_node_groups = merge({ ms = local.ms_group }, var.load_enabled ? { load = local.load_group } : {})
}

# --- Registro de imágenes ---
resource "aws_ecr_repository" "ingest" {
  name         = "${var.name}/ingest-ms"
  force_delete = true # permite destruir aunque tenga imágenes
  image_scanning_configuration { scan_on_push = true }
}

# --- Cola, DLQ, tabla de idempotencia y Lambda: los mismos módulos que en LocalStack ---
module "stack" {
  source                = "../../modules/stack"
  prefix                = var.name
  reconciler_source_dir = "${path.module}/../../../services/reconciler-lambda"
}

# --- Permisos por pod (IRSA) ---
resource "aws_iam_policy" "ingest_send" {
  name   = "${var.name}-ingest-send"
  policy = module.stack.ingest_send_policy_json # solo sqs:SendMessage sobre la cola de ingesta
}

module "ingest_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.60.0"

  role_name        = "${var.name}-ingest-ms"
  role_policy_arns = { send = aws_iam_policy.ingest_send.arn }
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["default:ingest-ms"]
    }
  }
}

module "autoscaler_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.60.0"

  role_name                        = "${var.name}-cluster-autoscaler"
  attach_cluster_autoscaler_policy = true
  cluster_autoscaler_cluster_names = [module.eks.cluster_name]
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:cluster-autoscaler"]
    }
  }
}

# --- Guardrail de costo ---
resource "aws_budgets_budget" "poc" {
  count        = var.create_budget ? 1 : 0
  name         = "${var.name}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_email]
  }
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_email]
  }
}
