#!/bin/bash
# U-03 계정 잠금 임계값 설정
# 사용법: ./u03_account_lockout.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U03
    ;;
  fix)
    if declare -F fix_U03 > /dev/null; then
      fix_U03
      check_U03
    else
      check_U03
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
