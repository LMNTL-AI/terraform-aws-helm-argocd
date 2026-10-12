resource "helm_release" "this" {
  name             = "argocd"
  namespace        = var.argocd_namespace
  repository       = var.chart_url
  chart            = "argo-cd"
  version          = var.chart_version
  max_history      = 3
  create_namespace = true
  values           = [local.manifest]
}

resource "kubernetes_secret" "github_app" {
  metadata {
    namespace = var.argocd_namespace
    name      = lower(var.github_app.secret_name)

    labels = {
      "argocd.argoproj.io/secret-type" = "repo-creds"
    }
  }

  data = {
    type                    = "git"
    url                     = "https://github.com/${var.github_app.organization}"
    githubAppID             = var.github_app.app_id
    githubAppInstallationID = var.github_app.installation_id
    githubAppPrivateKey     = var.github_app.private_key
  }

  depends_on = [helm_release.this]
}

resource "kubernetes_secret" "repository" {
  for_each = toset(var.repositories)
  metadata {
    namespace = var.argocd_namespace
    name      = lower("argocd-${replace(each.value, "/", "-")}")

    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  data = {
    type = "git"
    url  = "https://github.com/${each.value}"
  }

  depends_on = [helm_release.this]
}

# The dex GitHub connector's client secret lives in its own Secret, not inline in
# argocd-cm. Inline, it was readable by anyone who can read ConfigMaps in this
# namespace, and it rode the Helm values into helm_release metadata, which a
# Terraform plan prints from state. dex.config references it as
# $argocd-dex-github:dex.github.clientSecret; Argo CD resolves that only for a
# Secret labelled app.kubernetes.io/part-of=argocd.
resource "kubernetes_secret" "oidc_github" {
  metadata {
    namespace = var.argocd_namespace
    name      = "argocd-dex-github"

    labels = {
      "app.kubernetes.io/part-of" = "argocd"
    }
  }

  data = {
    "dex.github.clientSecret" = var.oidc_github_client_secret
  }

  depends_on = [helm_release.this]
}

resource "kubernetes_secret" "external_github_oauth" {
  for_each = toset(keys(var.external_github_oauth_creds))
  metadata {
    namespace = var.argocd_namespace
    name      = "github-oauth-${each.key}"

    labels = {
      "app.kubernetes.io/part-of" = "argocd"
    }
  }

  data = {
    "dex.${each.key}.clientSecret" = var.external_github_oauth_creds[each.key].client_secret
  }

  depends_on = [helm_release.this]
}
