# Define um nome de rede para não usar a "default"
resource "google_compute_network" "main" {
  name                    = "${var.cluster_name}-network"
  auto_create_subnetworks = false
}

# Define uma sub-rede para o cluster
resource "google_compute_subnetwork" "main" {
  name          = "${var.cluster_name}-subnet"
  ip_cidr_range = "10.2.0.0/16"
  region        = var.gcp_region
  network       = google_compute_network.main.id
}

resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = "us-central1-f"
  project  = var.gcp_project_id

  # Vamos remover os nós default para usar um pool de nós gerenciado
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = google_compute_network.main.id
  subnetwork = google_compute_subnetwork.main.id

  workload_identity_config {
    workload_pool = "${var.gcp_project_id}.svc.id.goog"
  }
  }

resource "google_container_node_pool" "primary_nodes" {
  name       = "default-pool"
  project    = var.gcp_project_id
  location   = "us-central1-f"
  cluster    = google_container_cluster.primary.name
  node_count = 2

  node_config {
    machine_type = "e2-medium"
    disk_size_gb = "20"
       workload_metadata_config {
      mode = "GKE_METADATA"
    }
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
}
