# Домашнее задание к занятию «Вычислительные мощности. Балансировщики нагрузки» - `Мурчин Артем`

### Подготовка к выполнению задания

1. Домашнее задание состоит из обязательной части, которую нужно выполнить на провайдере Yandex Cloud, и дополнительной части в AWS (выполняется по желанию). 
2. Все домашние задания в блоке 15 связаны друг с другом и в конце представляют пример законченной инфраструктуры.  
3. Все задания нужно выполнить с помощью Terraform. Результатом выполненного домашнего задания будет код в репозитории. 
4. Перед началом работы настройте доступ к облачным ресурсам из Terraform, используя материалы прошлых лекций и домашних заданий.

---
## Задание 1. Yandex Cloud 

**Что нужно сделать**

1. Создать бакет Object Storage и разместить в нём файл с картинкой:

 - Создать бакет в Object Storage с произвольным именем (например, _имя_студента_дата_).
 - Положить в бакет файл с картинкой.
 - Сделать файл доступным из интернета.
 
2. Создать группу ВМ в public подсети фиксированного размера с шаблоном LAMP и веб-страницей, содержащей ссылку на картинку из бакета:

 - Создать Instance Group с тремя ВМ и шаблоном LAMP. Для LAMP рекомендуется использовать `image_id = fd827b91d99psvq5fjit`.
 - Для создания стартовой веб-страницы рекомендуется использовать раздел `user_data` в [meta_data](https://cloud.yandex.ru/docs/compute/concepts/vm-metadata).
 - Разместить в стартовой веб-странице шаблонной ВМ ссылку на картинку из бакета.
 - Настроить проверку состояния ВМ.
 
3. Подключить группу к сетевому балансировщику:

 - Создать сетевой балансировщик.
 - Проверить работоспособность, удалив одну или несколько ВМ.
4. (дополнительно)* Создать Application Load Balancer с использованием Instance group и проверкой состояния.

Полезные документы:

- [Compute instance group](https://registry.terraform.io/providers/yandex-cloud/yandex/latest/docs/resources/compute_instance_group).
- [Network Load Balancer](https://registry.terraform.io/providers/yandex-cloud/yandex/latest/docs/resources/lb_network_load_balancer).
- [Группа ВМ с сетевым балансировщиком](https://cloud.yandex.ru/docs/compute/operations/instance-groups/create-with-balancer).

## Решение 1. Yandex Cloud

Создал бакет Object Storage и разместил в нём файл с картинкой:

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

![](https://github.com/artmur1/23-02-hw/blob/main/img/23-2-01-01.png)

![](https://github.com/artmur1/23-02-hw/blob/main/img/23-2-01-02.png)

Создал группу ВМ в public подсети фиксированного размера с шаблоном LAMP и веб-страницей, содержащей ссылку на картинку из бакета:

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

![](https://github.com/artmur1/23-02-hw/blob/main/img/23-2-01-03.png)

![](https://github.com/artmur1/23-02-hw/blob/main/img/23-2-01-04.png)

Подключил группу к сетевому балансировщику:

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

![](https://github.com/artmur1/23-02-hw/blob/main/img/23-2-01-05.png)

Сетевой балансировщик работает. Адрес балансировщика http://130.193.45.81/. Загружается ВМ с адресом http://158.160.24.132/

![](https://github.com/artmur1/23-02-hw/blob/main/img/23-2-01-06.png)

Удалил 2 ВМ:

![](https://github.com/artmur1/23-02-hw/blob/main/img/23-2-01-07.png)

Через балансировщик загружается последняя оставшаяся ВМ с адресом http://158.160.68.93/:

![](https://github.com/artmur1/23-02-hw/blob/main/img/23-2-01-08.png)

Система работает.

---
## Задание 2*. AWS (задание со звёздочкой)

Это необязательное задание. Его выполнение не влияет на получение зачёта по домашней работе.

**Что нужно сделать**

Используя конфигурации, выполненные в домашнем задании из предыдущего занятия, добавить к Production like сети Autoscaling group из трёх EC2-инстансов с  автоматической установкой веб-сервера в private домен.

1. Создать бакет S3 и разместить в нём файл с картинкой:

 - Создать бакет в S3 с произвольным именем (например, _имя_студента_дата_).
 - Положить в бакет файл с картинкой.
 - Сделать доступным из интернета.
2. Сделать Launch configurations с использованием bootstrap-скрипта с созданием веб-страницы, на которой будет ссылка на картинку в S3. 
3. Загрузить три ЕС2-инстанса и настроить LB с помощью Autoscaling Group.

Resource Terraform:

- [S3 bucket](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket)
- [Launch Template](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template).
- [Autoscaling group](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_group).
- [Launch configuration](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_configuration).

Пример bootstrap-скрипта:

```
#!/bin/bash
yum install httpd -y
service httpd start
chkconfig httpd on
cd /var/www/html
echo "<html><h1>My cool web-server</h1></html>" > index.html
```
### Правила приёма работы

Домашняя работа оформляется в своём Git репозитории в файле README.md. Выполненное домашнее задание пришлите ссылкой на .md-файл в вашем репозитории.
Файл README.md должен содержать скриншоты вывода необходимых команд, а также скриншоты результатов.
Репозиторий должен содержать тексты манифестов или ссылки на них в файле README.md.
