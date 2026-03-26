terraform {
  required_providers {
    okta = {
      source  = "okta/okta"
      version = "~> 4.6"
    }
  }
}

provider "okta" {
  org_name  = var.okta_org_name
  base_url  = "okta.com"
  api_token = var.okta_api_token
}

# ── Groups ─────────────────────────────────────────────────────────────────────
resource "okta_group" "groups" {
  for_each    = var.groups
  name        = each.value.name
  description = each.value.description
}

# ── Users ──────────────────────────────────────────────────────────────────────
resource "okta_user" "users" {
  for_each   = var.users
  first_name = each.value.first_name
  last_name  = each.value.last_name
  login      = each.value.email
  email      = each.value.email
  status     = each.value.status
}

resource "okta_group_memberships" "user_groups" {
  for_each = var.users
  group_id = okta_group.groups[each.value.group].id
  users    = [okta_user.users[each.key].id]
}

# ── OIDC Application (example: internal dashboard) ─────────────────────────────
resource "okta_app_oauth" "internal_app" {
  label                     = var.app_label
  type                      = "web"
  grant_types               = ["authorization_code", "refresh_token"]
  redirect_uris             = var.app_redirect_uris
  post_logout_redirect_uris = var.app_post_logout_uris
  response_types            = ["code"]
  token_endpoint_auth_method = "client_secret_basic"
}

resource "okta_app_group_assignment" "app_groups" {
  for_each = var.app_groups
  app_id   = okta_app_oauth.internal_app.id
  group_id = okta_group.groups[each.value].id
}

# ── MFA Policy ─────────────────────────────────────────────────────────────────
resource "okta_policy_mfa" "default" {
  name            = "${var.environment}-mfa-policy"
  status          = "ACTIVE"
  description     = "Require MFA for all users in ${var.environment}"
  groups_included = [for g in okta_group.groups : g.id]

  okta_otp {
    enroll = "REQUIRED"
  }
  okta_push {
    enroll = "OPTIONAL"
  }
}

# ── Password Policy ────────────────────────────────────────────────────────────
resource "okta_policy_password" "default" {
  name            = "${var.environment}-password-policy"
  status          = "ACTIVE"
  groups_included = [for g in okta_group.groups : g.id]

  password_min_length           = 12
  password_min_lowercase        = 1
  password_min_uppercase        = 1
  password_min_number           = 1
  password_min_symbol           = 1
  password_history_count        = 10
  password_max_age_days         = 90
  password_expire_warn_days     = 14
}
