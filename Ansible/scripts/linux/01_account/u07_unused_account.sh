#!/bin/bash
# U-07 불필요한 계정 제거
# 사용법: ./u07_unused_account.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U07
    ;;
  fix)
    if declare -F fix_U07 > /dev/null; then
      fix_U07
      check_U07
    else
      check_U07
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
