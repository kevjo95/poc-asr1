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
    (soporte extendido). Consulta las versiones disponibles y su fecha de fin de soporte estándar antes de elegir:
      aws eks describe-cluster-versions --profile poc-asr1 --region us-east-1 --query 'clusterVersions[].[clusterVersion,status,endOfStandardSupportDate]' --output table
  EOT
}
variable "budget_email" {
  type        = string
  description = "Correo para la alarma de presupuesto."
}
variable "budget_usd" {
  type    = number
  default = 20
}
variable "ms_instance_type" {
  type        = string
  default     = "m7g.large" # 2 vCPU / 8 GiB, Graviton (arm64): coincide con la imagen compilada en Apple Silicon
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
  default = "c7g.xlarge" # 4 vCPU, aparte del MS para que el generador no compita con él
}
