#!/bin/bash
# U-37 crontab 설정파일 권한 설정 미흡
# 사용법: ./u37_crontab_perm.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U37
    ;;
  fix)
    if declare -F fix_U37 > /dev/null; then
      fix_U37
      check_U37
    else
      check_U37
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
