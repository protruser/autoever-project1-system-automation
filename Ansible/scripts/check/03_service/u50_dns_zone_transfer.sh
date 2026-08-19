#!/bin/bash
# U-50 DNS Zone Transfer 설정
# 사용법: ./u50_dns_zone_transfer.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U50
    ;;
  fix)
    if declare -F fix_U50 > /dev/null; then
      fix_U50
      check_U50
    else
      check_U50
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
