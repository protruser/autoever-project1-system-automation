#!/bin/bash
# lib/common.sh - KISA U-01~U-67 공통 엔진 라이브러리 (Ubuntu / Rocky Linux 전용)

# 1. items.sh 메타데이터 로드
# 주의: 여기서 쓰는 변수명은 'DIR'을 피한다 — main_runner.sh가 이 파일을
# source하는 caller이고 자신의 스크립트 루트 경로를 'DIR'에 담아 쓰는데,
# 여기서 DIR을 재정의하면 source 직후 caller의 DIR 값이 통째로 덮어써진다.
_COMMON_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$_COMMON_LIB_DIR/items.sh" ] && source "$_COMMON_LIB_DIR/items.sh"

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

# 3.5. JSON 문자열 이스케이프 (json_result의 5개 텍스트 필드가 공통으로 사용)
#
# 실측 버그: command_output 등에 설정 파일 내용을 그대로 담는 점검이 있는데
# (예: U-66 syslog 정책이 /etc/rsyslog.conf를 cat), 그 안에 탭 문자가 그대로
# 있으면 예전 버전은 줄바꿈/쌍따옴표만 이스케이프하고 탭은 손대지 않아서 JSON이
# 깨졌다 - "Invalid control character" 로 02_generate_report.py가 그 파일
# 전체를 통째로 건너뛰어 버려서(진단은 성공했는데 결과가 DB/화면에 하나도 안
# 올라오는 증상으로 나타남), 백슬래시도 원래 전혀 이스케이프하지 않고 있었다
# (main.py/02_generate_report.py의 _BAD_ESCAPE_RE 사후 보정이 바로 이 증상을
# 완화하려던 땜빵이었다 - 근본 원인은 여기였음).
#
# 순서가 중요하다: 백슬래시부터 먼저 이스케이프해야 뒤에서 추가하는 \t, \n 등의
# 백슬래시까지 다시 이스케이프되는 사고를 막는다. tr로 그 외 남는 제어문자(탭/CR/
# 개행 제외)는 아예 제거한다 - 리포트에 의미 있는 내용일 가능성이 거의 없고,
# 남겨봐야 JSON을 또 깨뜨릴 뿐이다.
_json_escape() {
  printf '%s' "$1" \
    | tr -d '\000-\010\013\014\016-\037' \
    | sed 's/\\/\\\\/g; s/\t/\\t/g; s/\r/\\r/g; s/"/\\"/g' \
    | sed ':a;N;$!ba;s/\n/\\n/g'
}

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

  # (일부 점검 함수는 command_output뿐 아니라 evidence_description 등
  #  다른 필드에도 여러 줄짜리 목록을 담기 때문에 5개 필드 모두 동일하게 처리한다.
  #  그렇지 않으면 문자열 안의 raw 개행이 JSON을 깨뜨리고, main_runner.sh의
  #  `tail -1` 캡처도 뒷부분만 잘라먹는다.)
  command_output=$(_json_escape "$command_output")
  command=$(_json_escape "$command")
  evidence_description=$(_json_escape "$evidence_description")
  recommendation_text=$(_json_escape "$recommendation_text")
  remediation_cmd=$(_json_escape "$remediation_cmd")

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

###
# --- [common.sh] 사전 점검 데이터 캐시 관리 ---

export TMP_U15="/tmp/u15.tmp"
export TMP_U25="/tmp/u25.tmp"
export TMP_U33="/tmp/u33.tmp"
export TMP_SVC="/tmp/svc.tmp"

generate_cache() {
  local target="${1:-all}" # 인자가 없으면 'all'로 동작

  case "$target" in
    all)
      # 1. 최초 1회 스캔 (main_runner.sh에서 호출)
      # 루트 파일시스템 전체 스캔을 단일 패스로 묶어 처리 (U-15, U-25)
      find / -xdev \
        \( \( -nouser -o -nogroup \) -fprint "$TMP_U15" \) , \
        \( -type f -perm -002 -fprint "$TMP_U25" \) 2>/dev/null
      
      # U-33은 /tmp, /var/tmp, /dev/shm 만 검사하므로 루트 스캔과 분리하여 즉시 처리
      find /tmp /var/tmp /dev/shm -maxdepth 2 \( -name '..*' -o -name '. *' -o -name '...*' \) ! -name '.' ! -name '..' -print 2>/dev/null > "$TMP_U33"
      
      # 전체 구동 중인 서비스 목록 캐싱
      systemctl list-units --type=service 2>/dev/null > "$TMP_SVC"
      ;;
      
    U-15)
      # 조치 후: 소유권이 root로 일괄 변경되었으므로 디스크 재스캔 없이 빈 파일로 만들어 '양호' 처리
      > "$TMP_U15"
      ;;
      
    U-25)
      # 조치 후: 타 사용자 쓰기 권한이 제거되었으므로 빈 파일로 만듦
      > "$TMP_U25"
      ;;
      
    U-33)
      # 조치 후: 의심 숨김 파일이 삭제되었으므로 빈 파일로 만듦
      > "$TMP_U33"
      ;;
      
    SVC)
      # 서비스 조치 후: 서비스 중지/비활성화 반영을 위해 1회 갱신 (명령어 실행 속도가 0.1초 내외로 매우 빠름)
      rm -f "$TMP_SVC"
      systemctl list-units --type=service 2>/dev/null > "$TMP_SVC"
      ;;
      
    *)
      echo "Unknown cache target: $target" >&2
      ;;
  esac
}

cleanup_cache() {
  rm -f "$TMP_U15" "$TMP_U25" "$TMP_U33" "$TMP_SVC"
}
###
