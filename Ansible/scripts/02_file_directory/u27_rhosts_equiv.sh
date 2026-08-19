#!/bin/bash
# U-27 $HOME/.rhosts, hosts.equiv 사용 금지
# 사용법: ./u27_rhosts_equiv.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U27
    ;;
  fix)
    if declare -F fix_U27 > /dev/null; then
      fix_U27
      check_U27
    else
      check_U27
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
