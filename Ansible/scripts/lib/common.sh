#!/bin/bash
# common.sh - KISA U-01~U-67 진단/조치 엔진 공통 함수 (Rocky/Ubuntu 등 Linux 공통)

HOSTNAME_VAL=$(hostname)
OS_TYPE="Linux"
OS_SPEC=$( (. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME") 2>/dev/null )
OS_SPEC=${OS_SPEC:-$(uname -sr)}

now() { date '+%Y-%m-%d %H:%M:%S'; }

# result 배열 한 항목(JSON) 출력. status: GOOD|FAIL|NA|ERR|CHECK
json_result() {
  local id="$1" status="$2" current="$3" expected="$4"
  current="${current//\"/\\\"}"
  expected="${expected//\"/\\\"}"
  printf '{"CheckID":"%s","status":"%s","Current_value":"%s","Expect_value":"%s","OS_type":"%s","OS_spec":"%s"}' \
    "$id" "$status" "$current" "$expected" "$OS_TYPE" "$OS_SPEC"
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

# 서비스가 설치되어 있지 않으면 해당 없음(NA)으로 취급
svc_disabled_or_absent() {
  local svc="$1"
  if ! svc_exists "$svc"; then
    echo "NA:not_installed"
    return
  fi
  if svc_active "$svc" || svc_enabled "$svc"; then
    echo "FAIL:active_or_enabled"
  else
    echo "GOOD:disabled"
  fi
}

svc_disable_now() {
  local svc="$1"
  svc_exists "$svc" && systemctl disable --now "$svc" &>/dev/null
}
