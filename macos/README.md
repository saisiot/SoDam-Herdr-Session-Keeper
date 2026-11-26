# 대화냥줍 macOS

Herdr에서 최근 60일의 Claude Code와 Codex 대화를 찾아 원래 작업 폴더에서 이어 엽니다. 제목, 폴더, 세션 ID를 검색하거나 도구별로 걸러 볼 수 있습니다.

## 설치와 실행

macOS에 Herdr 앱, `hc`, Node.js 22.13 이상과 사용하려는 AI CLI를 설치합니다. 저장소 루트에서 실행합니다.

```sh
macos/install.sh
```

Herdr 명령 팔레트에서 **대화냥줍**을 찾습니다. 실행 중인 Herdr에 터미널 명령으로 열 수도 있습니다.

```sh
herdr-app do mod.open '{"name":"sodam-conversation-picker"}'
```

`herdr-app` 명령이 PATH에 없다면 Herdr 앱 번들의 `Contents/MacOS/Herdr` 실행 파일을 사용합니다. 설치 시 기본 위치에서 앱이나 CLI를 찾지 못하면 `KEEPER_APP_EXE`, `KEEPER_HC_EXE`, `KEEPER_CLAUDE_EXE`, `KEEPER_CODEX_EXE`에 각 실행 파일의 절대 경로를 지정할 수 있습니다.

설치 파일은 `${HERDR_APP_HOME:-$HOME/.config/herdr-app}/mods/sodam-conversation-picker`에 저장됩니다. 다시 설치하거나 제거할 때 같은 `HERDR_APP_HOME`을 사용합니다.

```sh
macos/install.sh --uninstall
```

## 대화 이어서 열기

- **탭으로 이동**은 같은 세션이 Herdr에서 열려 있는지 다시 확인한 뒤 그 탭으로 이동합니다.
- **이어 열기**는 재개 명령을 원래 폴더의 새 Herdr 탭으로 전달합니다. Claude Code 또는 Codex가 실제로 대화를 이어 받았는지는 탭에서 확인합니다.
- 실행 중인 대화를 확실히 판별할 수 없을 때는 **명령 복사**를 사용할 수 있습니다. 실행 중인 다른 창이 없는지 확인하고 원래 작업 폴더의 터미널에서 붙여 넣습니다.

첫 버전은 사용자가 선택한 대화만 엽니다. 자동 복구와 원래 탭 배치 복원은 후속 범위입니다.
