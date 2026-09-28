# ---------------------------------------------------------------------------
# Self-service inputs (shown to users in the no-code provisioning form)
# ---------------------------------------------------------------------------

variable "name" {
  description = "Name of the server. Used for the instance Name tag and related resources."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{1,23}$", var.name))
    error_message = "name must be 2-24 characters: letters, digits and hyphens, starting with a letter."
  }
}

variable "server_type" {
  description = "Server role. Decides which network the VM joins. Web servers also get an NLB on port 8080."
  type        = string

  validation {
    condition     = contains(["Web", "App", "Bastion"], var.server_type)
    error_message = "server_type must be one of: Web, App, Bastion."
  }
}

variable "instance_size" {
  description = "T-shirt size of the server: micro, small, medium or large."
  type        = string
  #default     = "small"

  validation {
    condition     = contains(["micro", "small", "medium", "large"], var.instance_size)
    error_message = "instance_size must be one of: micro, small, medium, large."
  }
}

variable "cost_center" {
  description = "Cost center to charge. Applied as the CostCenter tag on every resource."
  type        = string

  validation {
    condition     = length(trimspace(var.cost_center)) > 0
    error_message = "cost_center must not be empty."
  }
}

variable "key_name" {
  description = "Existing EC2 key pair name, used to decrypt the Windows Administrator password. Leave empty to launch without one."
  type        = string
  default     = "test"
}

# ---------------------------------------------------------------------------
# Platform-team settings (set as workspace/variable-set defaults, usually
# hidden from self-service users)
# ---------------------------------------------------------------------------

variable "region" {
  description = "AWS region. Must match the region of the network-foundation stack."
  type        = string
  default     = "us-east-2"
}

variable "vpc_name" {
  description = "Name tag of the shared VPC created by network-foundation."
  type        = string
  default     = "selfservice-vpc"
}

variable "instance_types" {
  description = "Mapping of t-shirt size to EC2 instance type."
  type        = map(string)
  default = {
    micro  = "t3.micro"
    small  = "t3.small"
    medium = "t3.medium"
    large  = "t3.large"
  }
}

variable "windows_ami_ssm_parameter" {
  description = "Public SSM parameter that resolves to the latest Windows AMI."
  type        = string
  default     = "/aws/service/ami-windows-latest/Windows_Server-2022-English-Full-Base"
}

variable "rdp_allowed_cidrs" {
  description = "CIDRs allowed to RDP (3389) to the instance. Narrow this to your corporate range."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "web_allowed_cidrs" {
  description = "CIDRs allowed to reach the Web NLB on port 8080."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "root_volume_size" {
  description = "Root volume size in GiB."
  type        = number
  default     = 60
}
