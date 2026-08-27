#!/bin/bash
# U-30 UMASK 설정 관리
# 사용법: ./u30_umask.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U30
    ;;
  fix)
    if declare -F fix_U30 > /dev/null; then
      fix_U30
      check_U30
    else
      check_U30
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
