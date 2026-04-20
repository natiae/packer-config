# Packer + Tart 이미지 빌드 가이드

이 폴더는 로컬에서 React Native 빌드에 사용할 macOS `Tart` 이미지를 `Packer`로 생성하기 위한 설정 모음입니다.

목표는 다음과 같습니다.

- macOS VM 이미지를 반복 가능하게 생성하기
- Xcode / Android 빌드 환경을 계층적으로 관리하기
- 나중에 React Native 요구사항이 바뀌어도 변수와 파일 분리로 쉽게 수정하기

## Packer와 Tart가 무엇인가?

- `Tart`: Apple Silicon 환경에서 macOS 가상 머신 이미지를 다루는 도구입니다.
- `Packer`: VM 이미지를 코드로 정의하고, 같은 절차를 반복 실행할 수 있게 해주는 도구입니다.

이 저장소에서는 `Packer`가 각 `.pkr.hcl` 파일을 읽어서 `Tart` VM을 만들거나, 기존 VM을 기반으로 다음 단계 이미지를 생성합니다.

변경시 어려움이 있다면, tart를 관리하고 있는 [cirruslabs/macos-image-templates](https://github.com/cirruslabs/macos-image-templates?tab=readme-ov-file)를 살펴보는 것이 도움이 될 수 있습니다.

해당 레포지토리의 이미지를 클론받아도 되지만 flutter, github-action 등 복합적인 ci를 위한 이미지여서, 원치 않는 다양한 툴들이 깔려있을 수 있습니다.

## 왜 파일을 나눴나?

Tart의 VM 디스크는 sparse 파일로 저장됩니다. VM에 '100GB 디스크'를 할당해도, 실제로 데이터가 쓰인 부분만 디스크 공간을 차지합니다.

`ls -lh ~/.tart/vms/<image-name>`로 논리적 크기, `du -sh ~/.tart/vms/<image-name>`로 실제 점유크기를 확인할 수 있습니다.

Base VM을 clone할 때도, Base VM을 확장할 때도 이러한 동작은 유지됩니다.

예를 들어 tahoe.pkr.hcl을 이용해서, 순수하게 tahoe가 설치된 이미지를 생성하고, 이를 base로 새로운 이미지에 xcode를 설치해도, tahoe os가 설치된 APFS 공간이 새로히 생성되는 것이 아닙니다.

따라서 여기서 이미지 빌드과정을 쪼개는 것은

    - 이미지 생성과정에서, try-catch의 용이함
    - 이미지의 구성 요소 변경시의 변경 최소화. 빌드 시간 단축
    

등의 다양한 장점을 노릴 수 있습니다.

## 사용 예시

### MacOS Download

여기에서 사용되는 boot_command는 macOS의 ui에 따라 상당히 다르고. 또한 오래걸립니다.

다운받은 이미지를 최대한 보존하는 것이 좋습니다.

사용한 macOS버전 등을 변경하고 싶다면, [cirruslabs/macos-image-templates](https://github.com/cirruslabs/macos-image-templates?tab=readme-ov-file)의 빌드파일을 수정하거나, 같은 레포지토리에서 제공하는 vanilla이미지를 클론받으세요.

```sh
tart clone ghcr.io/cirruslabs/macos-tahoe-vanilla:latest tahoe-vanilla

```

tart에서 설정을 하기 위해서, ssh를 이용합니다.

아래의 단계들을 진행하면서 ssh 연결을 기다리다가 실패하는 경우, 혹은 위에서 받은 이미지를 실행하고 직접 ssh 연결을 시도했을 때 아래와 같은 호스트 키 검증 프롬프트가 발생하는 경우,

```plaintext
The authenticity of host '192.168.64.xxx (192.168.64.xxx)' can't be established.
ED25519 key fingerprint is:
SHA256:nnnnnnn
This host key is known by the following other names/addresses:
    ~/.ssh/known_hosts:n: 192.168.64.n
Are you sure you want to continue connecting (yes/no/[fingerprint])?

```

`~/.ssh/config`에 Tart VM 대역에 대해 호스트 키 검증을 끄는 설정을 추가해주세요.

```sh
Host 192.168.64.*
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR

```

> Tart VM은 매번 새로운 호스트 키를 가진 VM이 같은 IP 대역에 뜨기 때문에, 호스트 키 검증이 오히려 방해가 됩니다. 개발용 로컬 VM 대역이므로 검증을 꺼도 보안상 문제가 없습니다.

이미 `~/.ssh/known_hosts`에 충돌하는 엔트리가 저장되어 있다면 함께 정리해주세요.

```sh
sed -i.bak '/192\.168\.64\./d' ~/.ssh/known_hosts

```

### 환경 설정 도구 설치

이미지 내부에서 불필요한 서비스들을 비활성화합니다.

    - Spotlight
    - TimeMachine
    - Software Auto Update
    

이미지 내부에 빌드에 필요한 툴들을 설치할 수 있는 환경을 생성합니다.

    - github에 접근하기 위한 ssh 설정,
    - tool들을 설치하기 위한 homebrew
    - 개발환경을 쉽게 설치하고, 관리하기 위한 mise를 이용합니다.
    

```sh
cat > base.pkrvars.hcl <<EOF
base    = "tahoe-vanilla"
vm_name = "tahoe-base"
EOF
cat base.pkrvars.hcl
packer init base.pkr.hcl
packer build -var-file="base.pkrvars.hcl" base.pkr.hcl

```

### xcode 설정

xcode를 Tart VM내부에서 다운로드받게 되면, 다운로드된 압축된 xcode xip파일. 압축 해제된 xcode xip파일 등의 과정으로 디스크 사용량이 잠깐이지만 높아지고, 이로 인해 vm이 실제로 차지하게 되는 디스크 사용량이 많아집니다.

이를 방지하고, 이미지 빌드 실패시 다운로드를 줄이기 위해, 이미지를 빌드하는 pc에서 xcode를 다운로드 받고 해당 파일을 이용해 Tart VM에 xcode를 설치하도록 스크립트가 작성되어 있습니다.

`xcodes`를 이용하여 xip를 다운로드 하는것이 편리합니다.

`xcodes download <version> --directory ./XcodeCache`

다운로드한 파일의 이름은 `Xcode_<version>.xip`로 이름을 바꿔주세요.

```sh
echo -n "Apple ID: "
read APPLE_USER_ID

echo -n "Apple Password: "
read -s APPLE_USER_PASSWORD
echo

TARGET_XCODE_VERSION="26.3"
CACHE_DIR=".XcodeCache"
TARGET_FILE="$CACHE_DIR/Xcode_${TARGET_XCODE_VERSION}.xip"

cat > xcode.pkrvars.hcl <<EOF
base          = "tahoe-base"
xcode_version = "${TARGET_XCODE_VERSION}"
EOF

packer init xcode.pkr.hcl

XCODES_USERNAME="$APPLE_USER_ID" \
XCODES_PASSWORD="$APPLE_USER_PASSWORD" \
packer build -var-file="xcode.pkrvars.hcl" xcode.pkr.hcl

```

*Read the docs on [runme.dev](https://runme.dev/docs/intro) to learn how to get most out of Runme notebooks!*
