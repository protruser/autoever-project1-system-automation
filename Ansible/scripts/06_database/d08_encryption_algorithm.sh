#!/bin/bash
# D-08 안전한 암호화 알고리즘 사용
# 사용법: ./d08_encryption_algorithm.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/db_checks.sh"
source "$DIR/db_fixes.sh"

case "${1:-check}" in
  check)
    check_D08
    ;;
  fix)
    if declare -F fix_D08 > /dev/null; then
      fix_D08
      check_D08
    else
      check_D08
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
