#!/bin/bash
# U-58 불필요한 SNMP 서비스 구동 점검
# 사용법: ./u58_snmp_service.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U58
    ;;
  fix)
    if declare -F fix_U58 > /dev/null; then
      fix_U58
      check_U58
    else
      check_U58
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
