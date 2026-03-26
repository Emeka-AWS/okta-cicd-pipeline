# terraform/environments/dev/okta.tfvars
# Okta provisioning config — dev environment
# Sensitive values (api_token, org_url) are injected as TF_VAR_* from GitHub Secrets

environment    = "dev"
okta_org_name  = "mycompany-dev"   # replace with your Okta org subdomain
app_label      = "Internal Dashboard (dev)"

app_redirect_uris    = ["https://dev.internal.example.com/callback"]
app_post_logout_uris = ["https://dev.internal.example.com"]

app_groups = ["engineering", "devops"]

groups = {
  engineering = {
    name        = "Engineering"
    description = "Software engineers"
  }
  devops = {
    name        = "DevOps"
    description = "Infrastructure and platform team"
  }
  readonly = {
    name        = "ReadOnly"
    description = "Read-only access — stakeholders and auditors"
  }
}

# Users are typically managed via SCIM/HR system sync in prod.
# For dev/demo, seed a few test users here.
users = {
  test_engineer = {
    first_name = "Test"
    last_name  = "Engineer"
    email      = "test.engineer@example.com"
    status     = "ACTIVE"
    group      = "engineering"
  }
}
