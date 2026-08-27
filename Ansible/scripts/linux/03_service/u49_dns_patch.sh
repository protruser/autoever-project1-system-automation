#!/bin/bash
# U-49 DNS 보안 버전 패치
# 사용법: ./u49_dns_patch.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U49
    ;;
  fix)
    if declare -F fix_U49 > /dev/null; then
      fix_U49
      check_U49
    else
      check_U49
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
