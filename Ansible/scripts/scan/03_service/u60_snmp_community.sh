#!/bin/bash
# U-60 SNMP Community String 복잡성 설정
# 사용법: ./u60_snmp_community.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U60
    ;;
  fix)
    if declare -F fix_U60 > /dev/null; then
      fix_U60
      check_U60
    else
      check_U60
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
