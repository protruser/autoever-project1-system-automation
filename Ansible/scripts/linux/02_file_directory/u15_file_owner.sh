#!/bin/bash
# U-15 파일 및 디렉터리 소유자 설정
# 사용법: ./u15_file_owner.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U15
    ;;
  fix)
    if declare -F fix_U15 > /dev/null; then
      fix_U15
      check_U15
    else
      check_U15
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
