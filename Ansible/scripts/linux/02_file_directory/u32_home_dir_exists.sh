#!/bin/bash
# U-32 홈 디렉토리로 지정한 디렉토리의 존재 관리
# 사용법: ./u32_home_dir_exists.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U32
    ;;
  fix)
    if declare -F fix_U32 > /dev/null; then
      fix_U32
      check_U32
    else
      check_U32
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
