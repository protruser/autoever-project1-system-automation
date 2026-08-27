#!/bin/bash
# U-14 root 홈, 패스 디렉터리 권한 및 패스 설정
# 사용법: ./u14_root_path.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U14
    ;;
  fix)
    if declare -F fix_U14 > /dev/null; then
      fix_U14
      check_U14
    else
      check_U14
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
