packer {
  required_plugins {
    tart = {
      version = ">= 1.16.0"
      source  = "github.com/cirruslabs/tart"
    }
  }
}


variable "vm_name" {
  type = string
}

source "tart-cli" "tart" {
  vm_name      = "${var.vm_name}"
  cpu_count    = 6
  memory_gb    = 12
  ssh_username = "admin"
  ssh_password = "admin"
  ssh_timeout  = "120s"
}

build {
  sources = ["source.tart-cli.tart"]

  # ========================================
  # Android Command Line Tools 설치
  # ========================================
  provisioner "shell" {
    inline = [
      "source ~/.bash_profile",
      "brew install --cask android-commandlinetools",
    ]
  }

  # ========================================
  # ANDROID_HOME 환경변수 설정 (양쪽 프로필)
  # ========================================
  provisioner "shell" {
    inline = [
      "for f in ~/.zprofile ~/.bash_profile; do",
      "  echo 'export ANDROID_HOME=\"/opt/homebrew/share/android-commandlinetools\"' >> $f",
      "  echo 'export PATH=\"$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH\"' >> $f",
      "done",
    ]
  }

  # ========================================
  # 이미지 크기 최소화
  # ========================================
  provisioner "shell" {
    inline = [
      "source ~/.bash_profile",
      # sdkmanager 다운로드 캐시 제거
      "rm -rf $ANDROID_HOME/.downloadIntermediates || true",
      "rm -rf ~/.android/cache || true",
      # Homebrew 캐시 정리
      "brew cleanup --prune=all",
      "rm -rf ~/Library/Caches/Homebrew",
    ]
  }
}
