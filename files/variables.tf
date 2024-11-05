###cloud vars
variable "default_zone" {
  type        = string
  default     = "ru-central1-b"
  description = "https://cloud.yandex.ru/docs/overview/concepts/geo-scope"
}

variable "vm_resources" { 
  type         = map(map(number))
  default      = {
    nat_res = {
      cores = 2
      memory = 4
      core_fraction = 20
      disk_size = 20
    }
  }
}