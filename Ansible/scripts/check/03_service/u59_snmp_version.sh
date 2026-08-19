#!/bin/bash
# U-59 안전한 SNMP 버전 사용
# 사용법: ./u59_snmp_version.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U59
    ;;
  fix)
    if declare -F fix_U59 > /dev/null; then
      fix_U59
      check_U59
    else
      check_U59
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
