#!/bin/bash
# U-61 SNMP Access Control 설정
# 사용법: ./u61_snmp_acl.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U61
    ;;
  fix)
    if declare -F fix_U61 > /dev/null; then
      fix_U61
      check_U61
    else
      check_U61
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
