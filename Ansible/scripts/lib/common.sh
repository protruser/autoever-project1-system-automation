#!/bin/bash
# common.sh - KISA U-01~U-67 진단/조치 엔진 공통 함수 (Rocky Linux 9 기준)

HOSTNAME_VAL=$(hostname)
OS_TYPE="rocky"
OS_VERSION=$( (rpm -E %rhel 2>/dev/null) || echo "unknown")

now() { date '+%Y-%m-%d %H:%M:%S'; }

# JSON 한 줄 출력 (프로젝트 표준 스키마)
json_result() {
  local id="$1" category="$2" status="$3" current="$4" expected="$5"
  current="${current//\"/\\\"}"
  expected="${expected//\"/\\\"}"
  printf '{"check_id":"%s","category":"%s","status":"%s","current_value":"%s","expected_value":"%s","hostname":"%s","os_type":"%s","os_version":"%s","timestamp":"%s"}' \
    "$id" "$category" "$status" "$current" "$expected" "$HOSTNAME_VAL" "$OS_TYPE" "$OS_VERSION" "$(now)"
}

# 조치 전 백업 (원본 보존, 감사 대응용)
backup_file() {
  local f="$1"
  [ -f "$f" ] && cp -p "$f" "${f}.bak.$(date +%Y%m%d%H%M%S)"
}

perm_octal() { stat -c '%a' "$1" 2>/dev/null; }
owner_of()   { stat -c '%U' "$1" 2>/dev/null; }
group_of()   { stat -c '%G' "$1" 2>/dev/null; }

# 현재 권한이 max 이하인지 (숫자 비교, KISA 가이드의 "OOO 이하" 판단 기준)
perm_le() {
  local cur="$1" max="$2"
  [ -z "$cur" ] && return 1
  [ "$cur" -le "$max" ] 2>/dev/null
}

svc_active()  { systemctl is-active "$1" &>/dev/null; }
svc_enabled() { systemctl is-enabled "$1" &>/dev/null; }
svc_exists()  { systemctl list-unit-files --no-legend 2>/dev/null | awk '{print $1}' | grep -qx "$1"; }

# 서비스가 존재하지 않으면 이미 양호로 취급 (설치 안 된 서비스)
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
