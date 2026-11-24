variable "aws_profile" {
  type        = string
  description = "Perfil de AWS de la cuenta PERSONAL (p. ej. poc-asr1). Nunca un perfil de trabajo."
}
variable "region" {
  type    = string
  default = "us-east-1"
}
variable "name" {
  type    = string
  default = "poc-asr1"
}
variable "cluster_version" {
  type        = string
  description = <<-EOT
    Versión de Kubernetes de EKS. SIN valor por defecto a propósito: una versión fuera de soporte estándar cuesta ~6 veces más por hora
    (soporte extendido). Elegida el 23-nov: 1.36 (soporte estándar hasta 2027-08). Evitar 1.34 (acaba en dic-2026) y ≤ 1.33 (extendido). Consulta las versiones disponibles y su fecha de fin de soporte estándar antes de elegir:
      aws eks describe-cluster-versions --profile poc-asr1 --region us-east-1 --query 'clusterVersions[].[clusterVersion,status,endOfStandardSupportDate]' --output table
  EOT
}
variable "create_budget" {
  type        = bool
  default     = false
  description = "La cuenta ya tiene un presupuesto creado a mano; solo crea otro si se pone en true."
}
variable "budget_email" {
  type    = string
  default = ""
}
variable "budget_usd" {
  type    = number
  default = 20
}
variable "ms_instance_type" {
  type        = string
  default     = "m7i-flex.large" # 2 vCPU / 8 GiB, x86_64. Único tipo permitido para el MS en esta cuenta (plan gratuito)
  description = "Nodos del MS. Con 3096 MiB por pod caben 2 por nodo: 4 pods llenan 2 nodos y la ráfaga obliga a crear nodos nuevos."
}
variable "ms_min_nodes" {
  type    = number
  default = 2
}
variable "ms_max_nodes" {
  type    = number
  default = 6
}
variable "load_instance_type" {
  type    = string
  default = "c7i-flex.large" # 2 vCPU / 4 GiB, x86_64. Único tipo permitido para el generador
}
variable "load_enabled" {
  type        = bool
  default     = true
  description = "Nodo dedicado al generador de carga. Con cuota de 5 vCPU se pone en false y k6 corre en los nodos del MS."
}
variable "ami_type" {
  type    = string
  default = "AL2023_x86_64_STANDARD"
}
