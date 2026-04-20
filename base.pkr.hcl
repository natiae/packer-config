packer {
  required_plugins {
    tart = {
      version = ">= 1.16.0"
      source  = "github.com/cirruslabs/tart"
    }
  }
}

variable "base" {
  type = string
}

variable "vm_name" {
  type = string
}

source "tart-cli" "tart" {
  vm_base_name = "${var.base}"
  vm_name      = "${var.vm_name}"
  cpu_count    = 6
  memory_gb    = 8
  disk_size_gb = 80
  ssh_username = "admin"
  ssh_password = "admin"
  ssh_timeout  = "120s"
}

build {
  sources = ["source.tart-cli.tart"]

  # ========================================
  # 파일 디스크립터 제한 상향 (빌드 중 EMFILE 방지)
  # ========================================
  provisioner "file" {
    source      = "data/limit.maxfiles.plist"
    destination = "~/limit.maxfiles.plist"
  }

  provisioner "shell" {
    inline = [
      "echo 'Configuring maxfiles...'",
      "sudo mv ~/limit.maxfiles.plist /Library/LaunchDaemons/limit.maxfiles.plist",
      "sudo chown root:wheel /Library/LaunchDaemons/limit.maxfiles.plist",
      "sudo chmod 0644 /Library/LaunchDaemons/limit.maxfiles.plist",
    ]
  }

  # ========================================
  # 빌드 환경에 불필요한 시스템 서비스 비활성화
  # ========================================
  provisioner "shell" {
    inline = [
      "echo 'Disabling Spotlight indexing...'",
      "sudo mdutil -a -i off",

      "echo 'Disabling Time Machine local snapshots...'",
      "sudo tmutil disable || true",
      "sudo tmutil deletelocalsnapshots / || true",

      "echo 'Disabling automatic software updates...'",
      "sudo softwareupdate --schedule off",
    ]
  }

  # ========================================
  # 셸 설정 파일 준비 (zsh와 bash를 독립적으로 관리)
  # ========================================
  provisioner "shell" {
    inline = [
      "touch ~/.zprofile",
      "touch ~/.bash_profile",
    ]
  }

  # ========================================
  # Homebrew 설치 (공통 환경변수는 양쪽 프로필에 동일하게 추가)
  # ========================================
  provisioner "shell" {
    inline = [
      "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"",
      # 양쪽 프로필에 동일한 export 추가
      "for f in ~/.zprofile ~/.bash_profile; do",
      "  echo 'export LANG=en_US.UTF-8' >> $f",
      "  echo 'eval \"$(/opt/homebrew/bin/brew shellenv)\"' >> $f",
      "  echo 'export HOMEBREW_NO_AUTO_UPDATE=1' >> $f",
      "  echo 'export HOMEBREW_NO_INSTALL_CLEANUP=1' >> $f",
      "done",
    ]
  }

  # ========================================
  # GitHub을 known_hosts에 추가 (서브모듈/private repo 대응)
  # ========================================
  provisioner "shell" {
    inline = [
      "mkdir -p ~/.ssh",
      "chmod 700 ~/.ssh",
    ]
  }
  provisioner "file" {
    source      = "data/github_known_hosts"
    destination = "~/.ssh/known_hosts"
  }
  provisioner "shell" {
    inline = [
      "chmod 600 ~/.ssh/known_hosts",
    ]
  }

  # ========================================
  # Tart Guest Agent (--dir 공유, IP 보고, 시간 동기화)
  # ========================================
  provisioner "file" {
    source      = "data/tart-guest-daemon.plist"
    destination = "~/tart-guest-daemon.plist"
  }
  provisioner "file" {
    source      = "data/tart-guest-agent.plist"
    destination = "~/tart-guest-agent.plist"
  }
  provisioner "shell" {
    inline = [
      "source ~/.bash_profile",
      "brew install cirruslabs/cli/tart-guest-agent",

      # daemon variant
      "sudo mv ~/tart-guest-daemon.plist /Library/LaunchDaemons/org.cirruslabs.tart-guest-daemon.plist",
      "sudo chown root:wheel /Library/LaunchDaemons/org.cirruslabs.tart-guest-daemon.plist",
      "sudo chmod 0644 /Library/LaunchDaemons/org.cirruslabs.tart-guest-daemon.plist",

      # agent variant
      "sudo mv ~/tart-guest-agent.plist /Library/LaunchAgents/org.cirruslabs.tart-guest-agent.plist",
      "sudo chown root:wheel /Library/LaunchAgents/org.cirruslabs.tart-guest-agent.plist",
      "sudo chmod 0644 /Library/LaunchAgents/org.cirruslabs.tart-guest-agent.plist",
    ]
  }

  # ========================================
  # 이미지 크기 최소화: Homebrew 캐시 정리
  # ========================================
  provisioner "shell" {
    inline = [
      "source ~/.bash_profile",
      "brew cleanup --prune=all",
      "rm -rf ~/Library/Caches/Homebrew",
      "rm -rf /Users/admin/Library/Logs/Homebrew",
    ]
  }
}
