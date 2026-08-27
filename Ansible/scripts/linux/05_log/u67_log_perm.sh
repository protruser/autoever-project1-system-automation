#!/bin/bash
# U-67 로그 디렉터리 소유자 및 권한 설정
# 사용법: ./u67_log_perm.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U67
    ;;
  fix)
    if declare -F fix_U67 > /dev/null; then
      fix_U67
      check_U67
    else
      check_U67
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
