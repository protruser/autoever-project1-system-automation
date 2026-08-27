#!/bin/bash
# U-08 관리자 그룹에 최소한의 계정 포함
# 사용법: ./u08_admin_group.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U08
    ;;
  fix)
    if declare -F fix_U08 > /dev/null; then
      fix_U08
      check_U08
    else
      check_U08
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
