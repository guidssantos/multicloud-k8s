module "gcp_cluster" {
  count  = var.create_gcp_cluster ? 1 : 0
  source = "./modules/gcp"

  gcp_project_id = var.gcp_project_id
  gcp_region     = var.gcp_region
}

data "google_client_config" "gcp" {
  count = var.create_gcp_cluster ? 1 : 0
}

data "google_container_cluster" "primary" {
  count      = var.create_gcp_cluster ? 1 : 0
  name       = module.gcp_cluster[0].cluster_name
  location   = "us-central1-f"
  project    = var.gcp_project_id
  depends_on = [module.gcp_cluster]
}

provider "helm" {
  kubernetes {
    host                   = try(data.google_container_cluster.primary[0].endpoint, null) != null ? "https://${data.google_container_cluster.primary[0].endpoint}" : "https://127.0.0.1"
    cluster_ca_certificate = try(data.google_container_cluster.primary[0].master_auth[0].cluster_ca_certificate, null) != null ? base64decode(data.google_container_cluster.primary[0].master_auth[0].cluster_ca_certificate) : null
    token                  = try(data.google_client_config.gcp[0].access_token, null)
    insecure               = try(data.google_container_cluster.primary[0].endpoint, null) == null
  }
}

provider "kubernetes" {
  host                   = try(data.google_container_cluster.primary[0].endpoint, null) != null ? "https://${data.google_container_cluster.primary[0].endpoint}" : "https://127.0.0.1"
  cluster_ca_certificate = try(data.google_container_cluster.primary[0].master_auth[0].cluster_ca_certificate, null) != null ? base64decode(data.google_container_cluster.primary[0].master_auth[0].cluster_ca_certificate) : null
  token                  = try(data.google_client_config.gcp[0].access_token, null)
  insecure               = try(data.google_container_cluster.primary[0].endpoint, null) == null
}

resource "random_id" "bucket_suffix" {
  byte_length = 8
}

resource "google_storage_bucket" "landing_zone" {
  count         = var.create_gcp_cluster ? 1 : 0
  name          = "etl-landing-zone-${random_id.bucket_suffix.hex}"
  location      = var.gcp_region
  force_destroy = true
  project       = var.gcp_project_id
}

resource "google_storage_bucket" "processed_zone" {
  count         = var.create_gcp_cluster ? 1 : 0
  name          = "etl-processed-zone-${random_id.bucket_suffix.hex}"
  location      = var.gcp_region
  force_destroy = true
  project       = var.gcp_project_id
}

resource "google_service_account" "etl_app_sa" {
  count        = var.create_gcp_cluster ? 1 : 0
  account_id   = "etl-app-sa"
  display_name = "ETL App Service Account"
  project      = var.gcp_project_id
}

resource "google_storage_bucket_iam_member" "landing_reader_writer" {
  count  = var.create_gcp_cluster ? 1 : 0
  bucket = google_storage_bucket.landing_zone[0].name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.etl_app_sa[0].email}"
}

resource "google_storage_bucket_iam_member" "processed_reader_writer" {
  count  = var.create_gcp_cluster ? 1 : 0
  bucket = google_storage_bucket.processed_zone[0].name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.etl_app_sa[0].email}"
}

resource "kubernetes_service_account" "etl_app_sa" {
  count = var.create_gcp_cluster ? 1 : 0
  metadata {
    name      = "etl-app-sa"
    namespace = "default"
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.etl_app_sa[0].email
    }
  }
}

resource "google_service_account_iam_member" "etl_app_sa_wi_binding" {
  count              = var.create_gcp_cluster ? 1 : 0
  service_account_id = google_service_account.etl_app_sa[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.gcp_project_id}.svc.id.goog[default/${kubernetes_service_account.etl_app_sa[0].metadata[0].name}]"
}

resource "helm_release" "argocd" {
  count            = var.create_gcp_cluster ? 1 : 0
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  version          = "5.51.0"

  set {
    name  = "server.insecure"
    value = "true"
  }
}

/*
resource "kubernetes_manifest" "argocd_app_of_apps" {
  count    = var.create_gcp_cluster ? 1 : 0
  manifest = {
    "apiVersion" = "argoproj.io/v1alpha1"
    "kind"       = "Application"
    "metadata" = {
      "name"      = "root-app"
      "namespace" = "argocd"
    }
    "spec" = {
      "project" = "default"
      "source" = {
        "repoURL"        = "https://github.com/guidssantos/multicloud-k8s.git"
        "targetRevision" = "HEAD"
        "path"           = "kubernetes"
      }
      "destination" = {
        "server"    = "https://kubernetes.default.svc"
        "namespace" = "default"
      }
      "syncPolicy" = {
        "automated" = {
          "prune"    = true
          "selfHeal" = true
        }
        "syncOptions" = [
          "CreateNamespace=true"
        ]
      }
    }
  }
  depends_on = [helm_release.argocd]
}
*/

output "gcp_project_id" {
  description = "ID do projeto GCP"
  value       = var.gcp_project_id
}

output "landing_zone_bucket_name" {
  description = "Nome do bucket da landing zone"
  value       = var.create_gcp_cluster ? google_storage_bucket.landing_zone[0].name : null
}

output "processed_zone_bucket_name" {
  description = "Nome do bucket da processed zone"
  value       = var.create_gcp_cluster ? google_storage_bucket.processed_zone[0].name : null
}

output "argocd_server_url" {
  description = "URL para acessar o servidor do ArgoCD"
  value       = "http://${kubernetes_service.argocd_server_loadbalancer[0].status[0].load_balancer[0].ingress[0].ip}"
  sensitive   = false
}

resource "kubernetes_service" "argocd_server_loadbalancer" {
  count    = var.create_gcp_cluster ? 1 : 0
  metadata {
    name      = "argocd-server-loadbalancer"
    namespace = "argocd"
  }
  spec {
    selector = {
      "app.kubernetes.io/name" = "argocd-server"
    }
    port {
      protocol    = "TCP"
      port        = 80
      target_port = 8080
    }
    type = "LoadBalancer"
  }
  depends_on = [helm_release.argocd]
}