#!/bin/bash
# lib/common.sh - KISA U-01~U-67 공통 엔진 라이브러리 (Ubuntu / Rocky Linux 전용)

# 1. items.sh 메타데이터 로드
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$DIR/items.sh" ] && source "$DIR/items.sh"

# 2. 전역 환경변수(Global Variables) 선언 및 OS 자동 감지
HOSTNAME_VAL="$(hostname)"
OS_ID="unknown"
OS_VERSION="unknown"

if [ -f /etc/os-release ]; then
  . /etc/os-release
  case "$ID" in
    ubuntu)            OS_ID="ubuntu" ;;
    rocky|rhel|centos) OS_ID="rocky"  ;;
    *)                 OS_ID="unknown" ;;
  esac
  OS_VERSION="${VERSION_ID:-unknown}"
fi

export HOSTNAME_VAL OS_ID OS_VERSION

now() { date '+%Y-%m-%d %H:%M:%S'; }

# 3. items.sh 메타데이터 조회 함수
get_item_category() { grep -E "^${1}\|" <<< "$ITEMS" | cut -d'|' -f2; }
get_item_title()    { grep -E "^${1}\|" <<< "$ITEMS" | cut -d'|' -f3; }
get_item_autofix()  { grep -E "^${1}\|" <<< "$ITEMS" | cut -d'|' -f4; }

# 4. 확정된 11개 표준 필드 단일 행 JSON 출력 함수
json_result() {
  local code="$1"
  local category="$2"
  local title="$3"
  local importance="$4"
  local status="$5"
  local target_file="$6"
  local command="$7"
  local command_output="$8"
  local evidence_description="$9"
  local recommendation_text="${10}"
  local remediation_cmd="${11}"

  # 줄바꿈(\n) 및 쌍따옴표(\") 이스케이프 방어
  command_output=$(printf '%s' "$command_output" | sed ':a;N;$!ba;s/\n/\\n/g' | sed 's/"/\\"/g')
  command=$(printf '%s' "$command" | sed 's/"/\\"/g')
  evidence_description=$(printf '%s' "$evidence_description" | sed 's/"/\\"/g')
  recommendation_text=$(printf '%s' "$recommendation_text" | sed 's/"/\\"/g')
  remediation_cmd=$(printf '%s' "$remediation_cmd" | sed 's/"/\\"/g')

  printf '{"code":"%s","category":"%s","title":"%s","importance":"%s","status":"%s","target_file":"%s","command":"%s","command_output":"%s","evidence_description":"%s","recommendation_text":"%s","remediation_cmd":"%s"}\n' \
    "$code" "$category" "$title" "$importance" "$status" "$target_file" "$command" "$command_output" "$evidence_description" "$recommendation_text" "$remediation_cmd"
}

# 5. 파일 조치 전 백업 함수
backup_file() {
  local f="$1"
  [ -f "$f" ] && cp -p "$f" "${f}.bak.$(date +%Y%m%d%H%M%S)"
}

# 6. 파일 권한 및 소유권 점검 헬퍼
perm_octal() { stat -c '%a' "$1" 2>/dev/null; }
owner_of()   { stat -c '%U' "$1" 2>/dev/null; }
group_of()   { stat -c '%G' "$1" 2>/dev/null; }

perm_le() {
  local cur="$1" max="$2"
  [ -z "$cur" ] && return 1
  [ "$cur" -le "$max" ] 2>/dev/null
}

# 7. systemd 서비스 점검 헬퍼
svc_active()  { systemctl is-active "$1" &>/dev/null; }
svc_enabled() { systemctl is-enabled "$1" &>/dev/null; }
svc_exists()  { systemctl list-unit-files --no-legend 2>/dev/null | awk '{print $1}' | grep -qx "$1"; }

svc_disabled_or_absent() {
  local svc="$1"
  if ! svc_exists "$svc"; then
    echo "GOOD:not_installed"
    return
  fi
  if svc_active "$svc" || svc_enabled "$svc"; then
    echo "VULNERABLE:active_or_enabled"
  else
    echo "GOOD:disabled"
  fi
}

svc_disable_now() {
  local svc="$1"
  svc_exists "$svc" && systemctl disable --now "$svc" &>/dev/null
}
