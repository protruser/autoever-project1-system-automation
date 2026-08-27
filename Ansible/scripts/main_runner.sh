#!/bin/bash
# main_runner.sh - 카테고리 디렉토리의 u##_*.sh를 U번호 순으로 전부 실행하고 JSON으로 취합
# 사용법:
#   ./main_runner.sh check              # 전체 진단, JSON 배열을 stdout + /tmp/kisa_audit_result.json 에 출력
#   ./main_runner.sh fix                # 전체 조치(자동조치 항목만 실제 변경) + 재진단
#   ./main_runner.sh check /tmp/out.json  # 출력 파일 경로 지정



set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="${1:-check}"
OUTFILE="${2:-/tmp/kisa_audit_result.json}"
ANSIBLE_OS_NAME="${3:-}"
ANSIBLE_OS_VER="${4:-}"


# scripts/ 아래는 이제 "시스템 유형(linux/db/...)/NN_카테고리" 2단계 구조다
# (가이드가 Unix 서버 챕터와 DBMS 챕터를 완전히 별개 분류체계로 두는 것과
# 맞춰서, KISA 가이드 상세 상세가이드 검토 후 분리함 - 이전엔 06_database가
# 01_account 등 UNIX 카테고리와 같은 레벨에 있어서 어색했다). TYPE_DIRS 순서가
# 곧 실행 순서(및 결과 JSON 배열 순서)다 - 새 시스템 유형(예: windows)을
# 추가할 땐 여기 한 줄만 늘리면 된다. 카테고리(NN_이름)는 각 TYPE_DIR 안에서
# 여전히 자동 탐색한다.
TYPE_DIRS="linux db"

# --- 1. 호스트 정보 동적 수집 ---
H_HOSTNAME="${5:-$(hostname)}"
# IP 추출(VPN IP 추출) - 의도는 애초에 tailscale0 IP였는데, "127./192.168.0.
# 제외하고 첫 번째"라는 휴리스틱만 쓰다 보니 대상 서버에 tailscale0보다 먼저
# 잡히는 다른 인터페이스(예: DHCP로 새로 IP를 받은 로컬 LAN NIC, 192.168.100.x
# 등)가 생기면 그 IP가 뽑혀버린다 - host_facts가 IP를 기본 키로 쓰기 때문에
# 같은 서버가 매번 다른 "새 서버"로 잡히는 문제로 이어짐(autoever-5에서 실측
# 확인: ens33이 tailscale0보다 ifindex가 앞이라 ens33의 192.168.100.132가
# 뽑혔었다). tailscale0가 있으면 그 IP를 우선 쓰고, 없는 호스트(비-Tailscale
# 환경)만 기존 휴리스틱으로 폴백한다.
H_IP="$(ip -4 addr show tailscale0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1)"
if [ -z "$H_IP" ]; then
  H_IP="$(ip -4 addr show 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '^127\.' | grep -v '^192\.168\.0\.' | head -n 1)"
fi
# OS 추출 Ansible 인자가 있으면 우선 사용하고, 없으면 기존 uname 활용
if [ -n "$ANSIBLE_OS_NAME" ] && [ -n "$ANSIBLE_OS_VER" ]; then
    H_OS="$ANSIBLE_OS_NAME $ANSIBLE_OS_VER"
else
    H_OS="$(uname -s)"
fi

H_KERNEL="$(uname -r)"
H_ARCH="$(uname -m)"
# --- 사전 점검 데이터 추출 ---
source "$DIR/lib/common.sh"
generate_cache
# --- 2. 진단 스크립트 실행 및 결과 수집 ---
results=()
for type_dir in $TYPE_DIRS; do
  [ -d "$DIR/$type_dir" ] || continue
  CATEGORIES="$(find "$DIR/$type_dir" -maxdepth 1 -mindepth 1 -type d -name '[0-9]*_*' -exec basename {} \; | sort)"
  for cat in $CATEGORIES; do
    [ -d "$DIR/$type_dir/$cat" ] || continue
    # u01_xxx.sh(UNIX)뿐 아니라 d01_xxx.sh(DB) 등 다른 접두사 wrapper도
    # 같은 방식으로 실행되도록 카테고리 안의 .sh 전체를 대상으로 한다.
    for script in "$DIR/$type_dir/$cat"/*.sh; do
      [ -f "$script" ] || continue
      # 기존 코드와 동일하게 각 스크립트의 출력을 캡처
      line="$(bash "$script" "$MODE" 2>/dev/null | tail -1)"
      [ -z "$line" ] && continue
      results+=("$line")
    done
  done
done


# --- 사전 점검 데이터 삭제 ---
###
cleanup_cache
###
# --- 3. 최종 JSON 포맷 조립 및 파일 저장 ---
{
  printf '{\n'
  printf '  "host_info": {\n'
  printf '    "hostname": "%s",\n' "$H_HOSTNAME"
  printf '    "ip": "%s",\n' "$H_IP"
  printf '    "os": "%s",\n' "$H_OS"
  printf '    "kernel": "%s",\n' "$H_KERNEL"
  printf '    "arch": "%s"\n' "$H_ARCH"
  printf '  },\n'
  printf '  "results": [\n'
  
  for i in "${!results[@]}"; do
    printf '    %s' "${results[$i]}"
    # 배열의 마지막 항목이 아닐 경우에만 쉼표(,) 추가[cite: 3]
    [ "$i" -lt $((${#results[@]}-1)) ] && printf ','
    printf '\n'
  done
  
  printf '  ]\n'
  printf '}\n'
} > "$OUTFILE"

echo "# saved: $OUTFILE ($(( ${#results[@]} )) items)" >&2
