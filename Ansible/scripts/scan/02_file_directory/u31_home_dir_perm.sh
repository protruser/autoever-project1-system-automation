#!/bin/bash
# U-31 홈 디렉토리 소유자 및 권한 설정
# 사용법: ./u31_home_dir_perm.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U31
    ;;
  fix)
    if declare -F fix_U31 > /dev/null; then
      fix_U31
      check_U31
    else
      check_U31
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
