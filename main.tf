terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
  required_version = ">= 0.13"
}

provider "yandex" {
  cloud_id                 = "b1g7vc0qhepoquep2qb3"
  folder_id                = "b1gc94tgq747qlg0l7af"
  service_account_key_file = "/home/aza/key.json"
  zone = "ru-central1-e"
}

resource "yandex_compute_disk" "disk" {
  name     = "disk"
  type     = "network-hdd"
  zone     = "ru-central1-e"
  size     = "20"
  image_id = "fd83j4siasgfq4pi1qif"
}

# Данные о существующей сети
  data "yandex_vpc_network" "existing-network" {
  name = "default"  # Имя существующей сети
}

  # Данные о существующей подсети
  data "yandex_vpc_subnet" "existing-subnet" {
  name = "default-ru-central1-e"  # Имя существующей подсети
}

resource "yandex_compute_instance" "vm-7" {
  name = "kuba"
  platform_id = "standard-v2"
  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    disk_id = yandex_compute_disk.disk.id
  }

  network_interface {
    subnet_id = data.yandex_vpc_subnet.existing-subnet.id  # Используем существующую подсеть
    nat       = true
  }

  metadata = {
    user-data = "${file("meta.txt")}"
  }

  scheduling_policy {
    preemptible = true
  }
}

output "internal_ip_address_vm_1" {
  value = yandex_compute_instance.vm-7.network_interface.0.ip_address
}

output "external_ip_address_vm_1" {
  value = yandex_compute_instance.vm-7.network_interface.0.nat_ip_address
}

resource "null_resource" "baz" {
  connection {
    type = "ssh"
    user = "debian"
    host = yandex_compute_instance.vm-7.network_interface.0.nat_ip_address
    private_key = file ("/home/aza/aza")
  }
  

provisioner "remote-exec" {
    inline = [
    
      # Обновление списка пакетов, установка утилит
      "sudo apt update",
      "sudo apt -y install ca-certificates curl git",

      # Установка Docker и его утилит
      "sudo install -m 0755 -d /etc/apt/keyrings",
      "sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc",
      "sudo chmod a+r /etc/apt/keyrings/docker.asc",
      "echo 'deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian bookworm stable' | sudo tee /etc/apt/sources.list.d/docker.list",
      "sudo apt update",
      "sudo apt -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin",

      # Установка kubectl
      "curl -LO https://dl.k8s.io/v1.36.1/bin/linux/amd64/kubectl",
      "chmod +x kubectl",
      "sudo mv kubectl /usr/local/bin/kubectl",

      # Установка kind (версия 0.27 совместима с kubectl v1.36)
      "curl -Lo kind https://kind.sigs.k8s.io/dl/v0.27.0/kind-linux-amd64",
      "chmod +x kind",
      "sudo mv kind /usr/local/bin/kind",

      # Конфиг для kind-кластера (создаёт конфиг-файл для Kind-кластера с одной control-plane (master) нодой и одной worker нодой)
      "printf 'kind: Cluster\napiVersion: kind.x-k8s.io/v1alpha4\nnodes:\n- role: control-plane\n- role: worker\n' > kind-config.yaml",

      # Создание кластера kind с конфигурацией из созданного конфиг-файла
      "sudo kind create cluster --name project-test --config kind-config.yaml",

      # Перенос kubeconfig в домашнюю директорию пользователя debian
      "sudo mkdir -p /home/debian/.kube",
      "sudo cp /root/.kube/config /home/debian/.kube/config",
      "sudo chown -R debian:debian /home/debian/.kube",

      # Установка Helm
      "curl -fsSL https://get.helm.sh/helm-v4.2.3-linux-amd64.tar.gz -o helm.tar.gz",
      "tar -xzf helm.tar.gz",
      "sudo mv linux-amd64/helm /usr/local/bin/helm",
      "rm -rf linux-amd64 helm.tar.gz",
      "helm version",

      # Скачиваем Gatekeeper из Yandex Container Registry
      "helm pull oci://cr.yandex/yc-marketplace/yandex-cloud/gatekeeper/gatekeeper --version 3.20.1 --untar",

      # Устанавливаем Gatekeeper через локальный чарт
      "helm install gatekeeper ./gatekeeper/ --namespace gatekeeper-system --create-namespace",
      
      "sudo mkdir -p /home/debian/gatekeeper/constraints",
      "sudo chown -R debian:debian /home/debian/gatekeeper/constraints",
      "sudo chmod -R 755 /home/debian/gatekeeper/constraints",
    ]
  }

# Копируем файлы
provisioner "file" {
  source      = "${path.module}/Gatekeeper/constraints/"  
  destination = "/home/debian/gatekeeper/constraints"
}
provisioner "file" {
  source      = "${path.module}/Gatekeeper/templates/"  
  destination = "/home/debian/gatekeeper/templates"
}

  triggers = {
    always_run = timestamp()
  }
}
