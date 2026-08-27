#!/bin/bash
# db_fixes.sh - DBMS(D-01~D-26 중 이 인프라 대상 항목) 조치 함수
# checks.sh/fixes.sh(UNIX 67개 항목)와 분리된 이유는 db_checks.sh 상단 주석 참고.
#
# u0x 계열과 동일한 컨벤션을 따른다: 항목마다 fix_Dxx()를 전부 정의해두고,
# 함수 맨 앞에서 items.sh의 자동조치여부를 확인해 1이 아니면 즉시 return한다.
# (autofix=0 항목도 함수 자체는 존재해야 wrapper의 `declare -F fix_Dxx` 분기가
# 일관되게 동작한다 - U-05 등 기존 UNIX 항목과 동일한 패턴.)
#
# DB 계정/비밀번호를 새로 발급하거나, 어떤 계정을 지울지 같은 "개별 판단"이
# 필요한 항목(D-01,02,04,06,07,08,10,20,25)은 자동조치 대상이 아니다 - check
# 결과의 recommendation_text/remediation_cmd로 수동 조치 가이드만 제공한다.

fix_D01() { local code="D-01"; local autofix_flag="$(get_item_autofix "$code")"; [ "$autofix_flag" != "1" ] && return 0; }
fix_D02() {
  local code="D-02"; local autofix_flag="$(get_item_autofix "$code")"
  [ "$autofix_flag" != "1" ] && return 0
  case "$(_db_engine)" in
    mysql)
      _mysql_ok || return 0
      local h
      for h in $(_mysql_q "SELECT host FROM mysql.user WHERE user='';"); do
        _mysql_q "DROP USER ''@'${h}';" >/dev/null
      done
      _mysql_q "FLUSH PRIVILEGES;" >/dev/null
      ;;
    postgresql)
      _pg_ok || return 0
      local r
      for r in test guest demo; do _pg_q "DROP ROLE IF EXISTS \"${r}\";" >/dev/null; done
      ;;
  esac
}
fix_D04() {
  local code="D-04"; local autofix_flag="$(get_item_autofix "$code")"
  [ "$autofix_flag" != "1" ] && return 0
  case "$(_db_engine)" in
    mysql)
      _mysql_ok || return 0
      local user host
      while IFS=$'\t' read -r user host; do
        [ -z "$user" ] && continue
        _mysql_q "REVOKE ALL PRIVILEGES, GRANT OPTION ON *.* FROM '${user}'@'${host}';" >/dev/null
      done <<< "$(_mysql_q "SELECT user,host FROM mysql.user WHERE (Super_priv='Y' OR Grant_priv='Y') AND user NOT IN ('root','mysql.sys','mysql.session','mysql.infoschema','mariadb.sys');")"
      _mysql_q "FLUSH PRIVILEGES;" >/dev/null
      ;;
    postgresql)
      # PostgreSQL은 SUPERUSER 회수가 앱/운영 계정 연동을 끊을 수 있어 자동조치하지 않는다.
      # check_D04가 status="검토"로 표시하여 관리자가 수동 확인·조치하도록 안내한다.
      return 0
      ;;
  esac
}
fix_D06() { local code="D-06"; local autofix_flag="$(get_item_autofix "$code")"; [ "$autofix_flag" != "1" ] && return 0; }
fix_D07() { local code="D-07"; local autofix_flag="$(get_item_autofix "$code")"; [ "$autofix_flag" != "1" ] && return 0; }
fix_D08() {
  local code="D-08"; local autofix_flag="$(get_item_autofix "$code")"
  [ "$autofix_flag" != "1" ] && return 0
  case "$(_db_engine)" in
    mysql)
      _mysql_ok || return 0
      _mysql_q "INSTALL PLUGIN auth_socket SONAME 'auth_socket.so';" >/dev/null 2>&1
      # root@localhost -> auth_socket(OS 인증) 전환만 자동으로 한다. 다른
      # 계정까지 caching_sha2_password로 바꾸려면 새 비밀번호가 필요한데,
      # 여기서 즉석으로 만든 값은 어디에도 남기지 않으면 그 계정을 그 자리에서
      # 복구 불가능하게 잠가버린다(실측된 문제 - items.sh D-08 설명 참고).
      # 그런 계정은 check_D08의 evidence/recommendation_text로만 안내하고
      # 실제 비밀번호 교체는 관리자가 수동으로 한다.
      local root_plugin
      root_plugin="$(_mysql_q "SELECT plugin FROM mysql.user WHERE user='root' AND host='localhost';")"
      if [ "$root_plugin" = "mysql_native_password" ]; then
        _mysql_q "ALTER USER 'root'@'localhost' IDENTIFIED WITH auth_socket;" >/dev/null 2>&1
      fi
      _mysql_q "FLUSH PRIVILEGES;" >/dev/null
      ;;
    postgresql)
      _pg_ok || return 0
      _pg_q "ALTER SYSTEM SET password_encryption='scram-sha-256';" >/dev/null
      _pg_q "SELECT pg_reload_conf();" >/dev/null
      ;;
  esac
}
fix_D10() {
  local code="D-10"; local autofix_flag="$(get_item_autofix "$code")"
  [ "$autofix_flag" != "1" ] && return 0
  case "$(_db_engine)" in
    mysql)
      _mysql_ok || return 0
      local user host
      while IFS=$'\t' read -r user host; do
        [ -z "$user" ] && continue
        _mysql_q "DROP USER '${user}'@'${host}';" >/dev/null
      done <<< "$(_mysql_q "SELECT user,host FROM mysql.user WHERE host='%' AND user NOT IN ('mysql.sys','mysql.session','mysql.infoschema','mariadb.sys');")"
      _mysql_q "FLUSH PRIVILEGES;" >/dev/null
      ;;
    postgresql)
      # PostgreSQL은 listen_addresses 제한이 원격 앱 연동을 끊을 수 있어 자동조치하지 않는다.
      # check_D10이 status="검토"로 표시하여 관리자가 수동 확인·조치하도록 안내한다.
      return 0
      ;;
  esac
}
fix_D20() { local code="D-20"; local autofix_flag="$(get_item_autofix "$code")"; [ "$autofix_flag" != "1" ] && return 0; }
fix_D25() { local code="D-25"; local autofix_flag="$(get_item_autofix "$code")"; [ "$autofix_flag" != "1" ] && return 0; }

# ============================================================
# D-03 비밀번호 사용기간 및 복잡도 - MySQL만 자동 조치(안전한 기본값 적용).
# PostgreSQL은 코어에 해당 정책 기능이 없어(db_checks.sh 참고) 조치 대상 없음.
# ============================================================
fix_D03() {
  local code="D-03"
  local autofix_flag="$(get_item_autofix "$code")"
  [ "$autofix_flag" != "1" ] && return 0

  [ "$(_db_engine)" = "mysql" ] || return 0
  _mysql_ok || return 0

  # 기관 정책에 맞춘 값이 아니라, 무제한(0)/미검증 상태를 벗어나기 위한
  # 안전한 기본값이다(90일 만료, 중간 강도 복잡도) - 실제 정책값은 관리자가
  # 이후 조정 가능하다.
  _mysql_q "SET GLOBAL default_password_lifetime=90;" >/dev/null
  if ! _mysql_q "SHOW VARIABLES LIKE 'validate_password%';" | grep -q .; then
    _mysql_q "INSTALL COMPONENT 'file://component_validate_password';" >/dev/null
  fi
  _mysql_q "SET GLOBAL validate_password.policy='MEDIUM';" >/dev/null 2>&1
}

# ============================================================
# D-11 DBA 이외 계정의 mysql 시스템 스키마 접근 제한 (MySQL만 해당)
# ============================================================
fix_D11() {
  local code="D-11"
  local autofix_flag="$(get_item_autofix "$code")"
  [ "$autofix_flag" != "1" ] && return 0

  [ "$(_db_engine)" = "mysql" ] || return 0
  _mysql_ok || return 0

  local rows grantee_host user host
  rows="$(_mysql_q "SELECT DISTINCT grantee FROM information_schema.schema_privileges WHERE table_schema='mysql' AND grantee NOT LIKE \"'root'@%\";")"
  [ -z "$rows" ] && return 0

  while IFS= read -r grantee_host; do
    [ -z "$grantee_host" ] && continue
    # grantee 형식: 'user'@'host' -> REVOKE 문에 그대로 사용 가능
    _mysql_q "REVOKE ALL PRIVILEGES ON mysql.* FROM ${grantee_host};" >/dev/null
  done <<< "$rows"
  _mysql_q "FLUSH PRIVILEGES;" >/dev/null
}

# ============================================================
# D-14 주요 설정 파일 권한을 640으로 강제 (MySQL/PostgreSQL 공통)
# ============================================================
fix_D14() {
  local code="D-14"
  local autofix_flag="$(get_item_autofix "$code")"
  [ "$autofix_flag" != "1" ] && return 0

  local engine; engine="$(_db_engine)"
  case "$engine" in
    mysql)
      for f in /etc/mysql/my.cnf /etc/my.cnf /etc/mysql/mysql.conf.d/mysqld.cnf; do
        [ -f "$f" ] || continue
        backup_file "$f"
        chmod 640 "$f"
      done
      ;;
    postgresql)
      _pg_ok || return 0
      # check_D14와 동일한 candidate_dirs 로직 - Debian/Ubuntu 패키징은 설정
      # 파일을 데이터 디렉터리가 아니라 /etc/postgresql/<버전>/main/에 따로
      # 두므로(check_D14 상단 주석 참고), data_directory만 보면 실측 대상
      # 환경(Ubuntu)에서 파일을 못 찾아 조치가 조용히 아무 일도 안 하는
      # 버그가 있었다 - 진단은 "취약"으로 잡히는데 조치는 늘 no-op이었음.
      local datadir; datadir="$(_pg_q "SHOW data_directory;")"
      local -a candidate_dirs=()
      [ -n "$datadir" ] && candidate_dirs+=("$datadir")
      for d in /etc/postgresql/*/main; do
        [ -d "$d" ] && candidate_dirs+=("$d")
      done
      [ ${#candidate_dirs[@]} -eq 0 ] && return 0
      local dir
      for dir in "${candidate_dirs[@]}"; do
        for f in "${dir}/postgresql.conf" "${dir}/pg_hba.conf" "${dir}/pg_ident.conf"; do
          [ -f "$f" ] || continue
          backup_file "$f"
          chmod 640 "$f"
        done
      done
      ;;
    *) return 0 ;;
  esac
}

# ============================================================
# D-18 PUBLIC에 부여된 테이블 권한 회수 (PostgreSQL만 해당)
# ============================================================
fix_D18() {
  local code="D-18"
  local autofix_flag="$(get_item_autofix "$code")"
  [ "$autofix_flag" != "1" ] && return 0

  [ "$(_db_engine)" = "postgresql" ] || return 0
  _pg_ok || return 0

  local rows entry schema_table
  rows="$(_pg_q "SELECT table_schema||'.'||table_name FROM information_schema.table_privileges WHERE grantee='PUBLIC' AND table_schema NOT IN ('pg_catalog','information_schema');")"
  [ -z "$rows" ] && return 0

  while IFS= read -r schema_table; do
    [ -z "$schema_table" ] && continue
    _pg_q "REVOKE ALL ON ${schema_table} FROM PUBLIC;" >/dev/null
  done <<< "$(echo "$rows" | sort -u)"
}

# ============================================================
# D-21 인가되지 않은 GRANT OPTION 회수 (MySQL만 해당)
# ============================================================
fix_D21() {
  local code="D-21"
  local autofix_flag="$(get_item_autofix "$code")"
  [ "$autofix_flag" != "1" ] && return 0

  [ "$(_db_engine)" = "mysql" ] || return 0
  _mysql_ok || return 0

  local rows user_host user host
  rows="$(_mysql_q "SELECT user,host FROM mysql.user WHERE grant_priv='Y' AND user NOT IN ('root','mysql.sys','mysql.session','mysql.infoschema','mariadb.sys');")"
  [ -z "$rows" ] && return 0

  while IFS=$'\t' read -r user host; do
    [ -z "$user" ] && continue
    _mysql_q "UPDATE mysql.user SET grant_priv='N' WHERE user='${user}' AND host='${host}';" >/dev/null
  done <<< "$rows"
  _mysql_q "FLUSH PRIVILEGES;" >/dev/null
}

# ============================================================
# D-26 감사 로그 활성화
# MySQL: general_log는 무중단으로 즉시 적용 가능해 바로 켠다.
# PostgreSQL: logging_collector는 서비스 재시작이 있어야 실제 반영되는
# 파라미터라, 설정값만 반영해두고(ALTER SYSTEM) 재시작은 자동으로 하지
# 않는다 - 배치성 조치 도중 서비스가 내려가면 다른 항목 점검/조치에도
# 영향을 줄 수 있어서다(U-01 reload 사례와 같은 이유).
# ============================================================
fix_D26() {
  local code="D-26"
  local autofix_flag="$(get_item_autofix "$code")"
  [ "$autofix_flag" != "1" ] && return 0

  local engine; engine="$(_db_engine)"
  case "$engine" in
    mysql)
      _mysql_ok || return 0
      _mysql_q "SET GLOBAL general_log='ON'; SET GLOBAL log_output='FILE';" >/dev/null
      ;;
    postgresql)
      # PostgreSQL의 logging_collector는 재시작해야 반영되고, 감사 기록 정책은
      # 기관 정책 영역이라 자동조치하지 않는다(check_D26이 status="검토"로 수동 안내).
      return 0
      ;;
    *) return 0 ;;
  esac
}
