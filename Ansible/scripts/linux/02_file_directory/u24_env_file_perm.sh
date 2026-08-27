#!/bin/bash
# U-24 사용자, 시스템 환경변수 파일 소유자 및 권한 설정
# 사용법: ./u24_env_file_perm.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U24
    ;;
  fix)
    if declare -F fix_U24 > /dev/null; then
      fix_U24
      check_U24
    else
      check_U24
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
