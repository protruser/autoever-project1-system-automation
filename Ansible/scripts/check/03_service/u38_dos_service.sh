#!/bin/bash
# U-38 DoS 공격에 취약한 서비스 비활성화
# 사용법: ./u38_dos_service.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U38
    ;;
  fix)
    if declare -F fix_U38 > /dev/null; then
      fix_U38
      check_U38
    else
      check_U38
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
