#!/bin/bash
# U-57 Ftpusers 파일 설정
# 사용법: ./u57_ftpusers.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U57
    ;;
  fix)
    if declare -F fix_U57 > /dev/null; then
      fix_U57
      check_U57
    else
      check_U57
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
