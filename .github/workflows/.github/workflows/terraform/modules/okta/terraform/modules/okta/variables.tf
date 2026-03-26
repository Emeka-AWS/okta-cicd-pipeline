variable "okta_org_name" {
  description = "Okta organisation subdomain (e.g. 'mycompany' for mycompany.okta.com)"
  type        = string
}

variable "okta_api_token" {
  description = "Okta API token — injected from GitHub Secrets, never stored in code"
  type        = string
  sensitive   = true
}

variable "environment" {
  description = "Deployment environment (dev | staging | prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod"
  }
}

variable "groups" {
  description = "Map of Okta groups to create"
  type = map(object({
    name        = string
    description = string
  }))
  default = {}
}

variable "users" {
  description = "Map of Okta users to provision"
  type = map(object({
    first_name = string
    last_name  = string
    email      = string
    status     = string
    group      = string
  }))
  default = {}
}

variable "app_label" {
  description = "Display name for the OIDC application in Okta"
  type        = string
}

variable "app_redirect_uris" {
  description = "Allowed redirect URIs for the OAuth application"
  type        = list(string)
}

variable "app_post_logout_uris" {
  description = "Post-logout redirect URIs"
  type        = list(string)
  default     = []
}

variable "app_groups" {
  description = "Set of group keys to assign to the application"
  type        = set(string)
  default     = []
}
