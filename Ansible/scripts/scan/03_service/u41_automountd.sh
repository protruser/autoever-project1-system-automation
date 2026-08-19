#!/bin/bash
# U-41 불필요한 automountd 제거
# 사용법: ./u41_automountd.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U41
    ;;
  fix)
    if declare -F fix_U41 > /dev/null; then
      fix_U41
      check_U41
    else
      check_U41
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
