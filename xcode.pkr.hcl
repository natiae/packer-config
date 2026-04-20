packer {
  required_plugins {
    tart = {
      version = ">= 1.12.0"
      source  = "github.com/cirruslabs/tart"
    }
  }
}

variable "base" {
  type        = string
  description = "Base VM name to clone from (e.g., 'tahoe-base')."
}

variable "xcode_version" {
  type        = string
  description = "Xcode version to install (e.g., '16.2')."
}

variable "xcode_components" {
  type        = list(string)
  default     = []
  description = "Additional Xcode components to download (e.g., ['iOS 17.5', 'watchOS 10.5'])."
}

variable "disk_size" {
  type    = number
  default = 60
}

source "tart-cli" "tart" {
  vm_base_name = var.base
  vm_name      = "${var.base}-xcode-${var.xcode_version}"
  cpu_count    = 4
  memory_gb    = 8
  disk_size_gb = var.disk_size
  headless     = true
  ssh_username = "admin"
  ssh_password = "admin"
  ssh_timeout  = "120s"
}

build {
  sources = ["source.tart-cli.tart"]

  # 1. xcodes CLI 설치
  provisioner "shell" {
    inline = [
      "source ~/.zprofile",
      "brew install xcodes",
      "xcodes version",
    ]
  }

  # 2. 호스트의 xip 파일을 VM으로 복사
  provisioner "file" {
    source      = pathexpand("~/XcodesCache/Xcode_${var.xcode_version}.xip")
    destination = "/Users/admin/Downloads/Xcode.xip"
  }

  # 3. 복사 후 디스크 상태 확인
  provisioner "shell" {
    inline = ["df -h"]
  }

  # 4. Xcode 설치 + 기본 설정
  provisioner "shell" {
    inline = [
      "source ~/.zprofile",
      "sudo xcodes install ${var.xcode_version} --experimental-unxip --path /Users/admin/Downloads/Xcode.xip --select --empty-trash",

      # 설치된 Xcode를 /Applications/Xcode_<version>.app로 이름 변경 (GitHub Actions 호환 경로)
      "INSTALLED_PATH=$(xcodes select -p)",
      "APP_DIR=$(dirname $(dirname $INSTALLED_PATH))",
      "sudo mv $APP_DIR /Applications/Xcode_${var.xcode_version}.app",
      "sudo xcode-select -s /Applications/Xcode_${var.xcode_version}.app",

      "xcodebuild -downloadPlatform iOS",
      "xcodebuild -runFirstLaunch",

      # 설치 파일 정리
      "rm -f /Users/admin/Downloads/Xcode.xip",
      "df -h",
    ]
  }

  # 5. 추가 Xcode 컴포넌트 (선택)
  provisioner "shell" {
    inline = concat(
      ["source ~/.zprofile"],
      [for component in var.xcode_components : "xcodebuild -downloadComponent ${component}"]
    )
  }

  # 6. apsd 데몬 비활성화 (부팅 후 CPU 사용 문제 완화)
  #    참고: https://iboysoft.com/wiki/apsd-mac.html
  #         https://discussions.apple.com/thread/4459153
  provisioner "shell" {
    inline = [
      "sudo launchctl unload -w /System/Library/LaunchDaemons/com.apple.apsd.plist"
    ]
  }
}
