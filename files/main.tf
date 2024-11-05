terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
}

provider "yandex" {
  zone = var.default_zone
}

// Create SA
resource "yandex_iam_service_account" "sa" {
  folder_id = local.folder_id
  name      = "tf-test-sa"
}

// Grant permissions
resource "yandex_resourcemanager_folder_iam_member" "sa-editor" {
  folder_id = local.folder_id
  role      = "editor"
  member    = "serviceAccount:${yandex_iam_service_account.sa.id}"
}

// Create Static Access Keys
resource "yandex_iam_service_account_static_access_key" "sa-static-key" {
  service_account_id = yandex_iam_service_account.sa.id
  description        = "static access key for object storage"
}

// Use keys to create bucket

resource "yandex_storage_bucket" "murchin-03-11-2024" {
  access_key = yandex_iam_service_account_static_access_key.sa-static-key.access_key
  secret_key = yandex_iam_service_account_static_access_key.sa-static-key.secret_key
  bucket     = "murchin-03-11-2024"
  acl    = "public-read"
  website {
    index_document = "kitten1.jpg"
#    error_document = "error.html"
  }

  anonymous_access_flags {
    read        = true
    list        = true
    config_read = true
  }
}

resource "yandex_storage_object" "cute-cat-picture2" {
  bucket = "murchin-03-11-2024"
  key    = "kitten1.jpg"
  source = "./images/kitten1.jpg"
  tags = {
    test = "value"
  }
}

resource "yandex_vpc_network" "murchin-net" {
  name = local.network_name
}

resource "yandex_vpc_subnet" "public" {
  name           = local.subnet_name1
  v4_cidr_blocks = ["192.168.10.0/24"]
  zone           = var.default_zone
  network_id     = yandex_vpc_network.murchin-net.id
}

resource "yandex_compute_instance_group" "group1" {
  name                = local.vm_lamp_name
  folder_id           = local.folder_id
  service_account_id  = yandex_iam_service_account.sa.id
  deletion_protection = false
  instance_template {
    platform_id = local.platform_id
    resources {
      core_fraction = var.vm_resources.nat_res.core_fraction
      memory        = var.vm_resources.nat_res.memory
      cores         = var.vm_resources.nat_res.cores
    }
    boot_disk {
      mode = "READ_WRITE"
      initialize_params {
        image_id = local.image_id
        size     = var.vm_resources.nat_res.disk_size
      }
    }

    scheduling_policy {
      preemptible = true
    }

    network_interface {
      network_id = yandex_vpc_network.murchin-net.id
      subnet_ids = ["${yandex_vpc_subnet.public.id}"]
      nat        = true
    }
    metadata = {
      foo      = "bar"
      user-data = "${file("./meta.yml")}"
    }
    network_settings {
      type = "STANDARD"
    }
  }

  scale_policy {
    fixed_scale {
      size = 3
    }
  }

  allocation_policy {
    zones = [var.default_zone]
  }

  deploy_policy {
    max_unavailable = 3
    max_creating    = 3
    max_expansion   = 3
    max_deleting    = 3
  }

  load_balancer {
    target_group_name        = "target-group"
    target_group_description = "Целевая группа Network Load Balancer"
  }

}

resource "yandex_lb_network_load_balancer" "lb-1" {
  name = "network-load-balancer-1"

  listener {
    name = "network-load-balancer-1-listener"
    port = 80
    external_address_spec {
      ip_version = "ipv4"
    }
  }

  attached_target_group {
    target_group_id = yandex_compute_instance_group.group1.load_balancer.0.target_group_id

    healthcheck {
      name = "http"
      http_options {
        port = 80
        path = "/index.html"
      }
    }
  }
}