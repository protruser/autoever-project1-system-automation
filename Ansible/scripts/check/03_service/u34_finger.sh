#!/bin/bash
# U-34 Finger 서비스 비활성화
# 사용법: ./u34_finger.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U34
    ;;
  fix)
    if declare -F fix_U34 > /dev/null; then
      fix_U34
      check_U34
    else
      check_U34
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
