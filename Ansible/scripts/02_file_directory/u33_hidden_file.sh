#!/bin/bash
# U-33 숨겨진 파일 및 디렉토리 검색 및 제거
# 사용법: ./u33_hidden_file.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U33
    ;;
  fix)
    if declare -F fix_U33 > /dev/null; then
      fix_U33
      check_U33
    else
      check_U33
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
