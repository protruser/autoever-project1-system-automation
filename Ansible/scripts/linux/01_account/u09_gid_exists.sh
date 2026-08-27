#!/bin/bash
# U-09 계정이 존재하지 않는 GID 금지
# 사용법: ./u09_gid_exists.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U09
    ;;
  fix)
    if declare -F fix_U09 > /dev/null; then
      fix_U09
      check_U09
    else
      check_U09
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
