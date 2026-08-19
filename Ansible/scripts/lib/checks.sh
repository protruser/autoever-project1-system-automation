#!/bin/bash
# checks.sh - U-01~U-67 진단(check) 함수. common.sh 로드 후 사용.
# 각 함수는 json_result 한 줄을 stdout에 출력한다.

# ===== 계정 관리 (U-01~U-17) =====

check_U01() {
  local f="/etc/ssh/sshd_config" val status
  val=$(grep -Ei '^\s*PermitRootLogin' "$f" 2>/dev/null | tail -1 | awk '{print $2}')
  val=${val:-yes}
  status="VULNERABLE"; [[ "$val" == "no" ]] && status="GOOD"
  json_result "U-01" "계정 관리" "$status" "PermitRootLogin $val" "PermitRootLogin no"
}

check_U02() {
  local f="/etc/login.defs" maxd minlen status current
  maxd=$(awk '/^PASS_MAX_DAYS/{print $2}' "$f" 2>/dev/null)
  minlen=$(grep -Po '(?<=minlen=)[0-9]+' /etc/security/pwquality.conf 2>/dev/null | tail -1)
  maxd=${maxd:-99999}; minlen=${minlen:-0}
  current="PASS_MAX_DAYS=$maxd, pwquality.minlen=$minlen"
  status="VULNERABLE"
  [ "$maxd" -le 90 ] 2>/dev/null && [ "$minlen" -ge 8 ] 2>/dev/null && status="GOOD"
  json_result "U-02" "계정 관리" "$status" "$current" "PASS_MAX_DAYS<=90, minlen>=8"
}

check_U03() {
  local f="/etc/security/faillock.conf" deny status
  deny=$(grep -Po '(?<=^deny = )[0-9]+' "$f" 2>/dev/null)
  deny=${deny:-0}
  status="VULNERABLE"
  [ "$deny" -ge 1 ] 2>/dev/null && [ "$deny" -le 5 ] 2>/dev/null && status="GOOD"
  json_result "U-03" "계정 관리" "$status" "deny=$deny" "deny 1~5"
}

check_U04() {
  local status current
  if [ -f /etc/shadow ] && awk -F: '$2=="x"{c++} END{exit !c}' /etc/passwd; then
    status="GOOD"; current="shadow 사용, passwd 2필드=x"
  else
    status="VULNERABLE"; current="passwd에 암호 해시 노출 가능"
  fi
  json_result "U-04" "계정 관리" "$status" "$current" "/etc/shadow 사용"
}

check_U05() {
  local list status
  list=$(awk -F: '$3==0 && $1!="root"{print $1}' /etc/passwd | paste -sd, -)
  status="GOOD"; [ -n "$list" ] && status="VULNERABLE"
  json_result "U-05" "계정 관리" "$status" "UID0_accounts=[${list}]" "root만 UID 0"
}

check_U06() {
  local status current
  if grep -Eq '^\s*auth\s+required\s+pam_wheel\.so' /etc/pam.d/su 2>/dev/null; then
    status="GOOD"; current="pam_wheel.so 적용됨"
  else
    status="VULNERABLE"; current="pam_wheel.so 미설정"
  fi
  json_result "U-06" "계정 관리" "$status" "$current" "wheel 그룹만 su 허용"
}

check_U07() {
  local list
  list=$(awk -F: '($7 !~ /nologin|false/) && $3>=1000 {print $1}' /etc/passwd | paste -sd, -)
  json_result "U-07" "계정 관리" "MANUAL" "로그인가능 계정=[${list}]" "불필요 계정 없음(수동 확인 필요)"
}

check_U08() {
  local members cnt
  members=$(getent group wheel | awk -F: '{print $4}')
  cnt=$(echo "$members" | tr ',' '\n' | grep -c .)
  json_result "U-08" "계정 관리" "MANUAL" "wheel_members=[${members}](${cnt}명)" "관리자 최소 인원(수동 확인 필요)"
}

check_U09() {
  local bad
  bad=$(awk -F: '{print $4}' /etc/passwd | sort -u | while read -r g; do getent group "$g" >/dev/null || echo "$g"; done | paste -sd, -)
  status="GOOD"; [ -n "$bad" ] && status="VULNERABLE"
  json_result "U-09" "계정 관리" "$status" "no_such_gid=[${bad}]" "모든 GID가 존재해야 함"
}

check_U10() {
  local dup
  dup=$(awk -F: '{print $3}' /etc/passwd | sort | uniq -d | paste -sd, -)
  status="GOOD"; [ -n "$dup" ] && status="VULNERABLE"
  json_result "U-10" "계정 관리" "$status" "dup_uid=[${dup}]" "UID 중복 없음"
}

check_U11() {
  local list
  list=$(awk -F: '$3>=1000 && $3!=65534 {print $1":"$7}' /etc/passwd | paste -sd, -)
  json_result "U-11" "계정 관리" "MANUAL" "user_shells=[${list}]" "불필요 계정은 nologin(수동 확인 필요)"
}

check_U12() {
  local tmout status
  tmout=$(grep -REo 'TMOUT=[0-9]+' /etc/profile /etc/profile.d/*.sh 2>/dev/null | head -1 | grep -Eo '[0-9]+$')
  tmout=${tmout:-0}
  status="VULNERABLE"
  [ "$tmout" -gt 0 ] 2>/dev/null && [ "$tmout" -le 600 ] 2>/dev/null && status="GOOD"
  json_result "U-12" "계정 관리" "$status" "TMOUT=$tmout" "TMOUT 1~600초"
}

check_U13() {
  local method status
  method=$(awk -F= '/^ENCRYPT_METHOD/{print $2}' /etc/login.defs 2>/dev/null | tr -d ' ')
  status="VULNERABLE"; [[ "$method" == "SHA512" ]] && status="GOOD"
  json_result "U-13" "계정 관리" "$status" "ENCRYPT_METHOD=${method:-미설정}" "ENCRYPT_METHOD SHA512"
}

check_U14() {
  local perm status
  perm=$(perm_octal /root)
  status="VULNERABLE"
  perm_le "$perm" 750 && ! echo "$PATH" | grep -q '(^|:)\.(:|$)' && status="GOOD"
  json_result "U-14" "파일 및 디렉터리 관리" "$status" "/root perm=$perm, PATH=$PATH" "/root<=750, PATH에 '.' 미포함"
}

check_U15() {
  local n
  n=$(find / -xdev \( -nouser -o -nogroup \) 2>/dev/null | wc -l)
  status="GOOD"; [ "$n" -gt 0 ] && status="MANUAL"
  json_result "U-15" "파일 및 디렉터리 관리" "$status" "소유자없는파일 ${n}개" "소유자/그룹 미존재 파일 없음"
}

check_U16() {
  local f="/etc/passwd" perm own status
  perm=$(perm_octal "$f"); own=$(owner_of "$f")
  status="VULNERABLE"
  [ "$own" == "root" ] && perm_le "$perm" 644 && status="GOOD"
  json_result "U-16" "파일 및 디렉터리 관리" "$status" "owner=$own,perm=$perm" "root:root, 644 이하"
}

check_U17() {
  local bad
  bad=$(find /etc/rc.d/init.d /usr/lib/systemd/system -maxdepth 1 -type f ! -user root -perm /go+w 2>/dev/null | paste -sd, -)
  status="GOOD"; [ -n "$bad" ] && status="VULNERABLE"
  json_result "U-17" "파일 및 디렉터리 관리" "$status" "위험파일=[${bad}]" "시작스크립트 root 소유, 그룹/기타 쓰기금지"
}

# ===== 파일 및 디렉터리 관리 (U-18~U-33) =====

check_U18() {
  local f="/etc/shadow" perm own status
  perm=$(perm_octal "$f"); own=$(owner_of "$f")
  status="VULNERABLE"
  [ "$own" == "root" ] && perm_le "$perm" 400 && status="GOOD"
  json_result "U-18" "파일 및 디렉터리 관리" "$status" "owner=$own,perm=$perm" "root:root, 400 이하"
}

check_U19() {
  local f="/etc/hosts" perm own status
  perm=$(perm_octal "$f"); own=$(owner_of "$f")
  status="VULNERABLE"
  [ "$own" == "root" ] && perm_le "$perm" 644 && status="GOOD"
  json_result "U-19" "파일 및 디렉터리 관리" "$status" "owner=$own,perm=$perm" "root:root, 644 이하"
}

check_U20() {
  local f status="GOOD" current="파일 없음(N/A)"
  for f in /etc/xinetd.conf /etc/inetd.conf; do
    [ -f "$f" ] || continue
    local perm own; perm=$(perm_octal "$f"); own=$(owner_of "$f")
    current="$f owner=$own,perm=$perm"
    status="VULNERABLE"; [ "$own" == "root" ] && perm_le "$perm" 600 && status="GOOD"
  done
  json_result "U-20" "파일 및 디렉터리 관리" "$status" "$current" "root:root, 600 이하"
}

check_U21() {
  local f status="GOOD" current="파일 없음(N/A)"
  for f in /etc/rsyslog.conf /etc/syslog.conf; do
    [ -f "$f" ] || continue
    local perm own; perm=$(perm_octal "$f"); own=$(owner_of "$f")
    current="$f owner=$own,perm=$perm"
    status="VULNERABLE"; [ "$own" == "root" ] && perm_le "$perm" 644 && status="GOOD"
  done
  json_result "U-21" "파일 및 디렉터리 관리" "$status" "$current" "root:root, 644 이하"
}

check_U22() {
  local f="/etc/services" perm own status
  perm=$(perm_octal "$f"); own=$(owner_of "$f")
  status="VULNERABLE"
  [ "$own" == "root" ] && perm_le "$perm" 644 && status="GOOD"
  json_result "U-22" "파일 및 디렉터리 관리" "$status" "owner=$own,perm=$perm" "root:root, 644 이하"
}

check_U23() {
  local n
  n=$(find / -xdev \( -perm -4000 -o -perm -2000 \) -type f 2>/dev/null | wc -l)
  json_result "U-23" "파일 및 디렉터리 관리" "MANUAL" "SUID/SGID 파일 ${n}개" "불필요 SUID/SGID 제거(수동 확인 필요)"
}

check_U24() {
  local bad
  bad=$(find /etc/profile /etc/bashrc /etc/profile.d -type f ! -user root -o -type f -perm /o+w 2>/dev/null | paste -sd, -)
  status="GOOD"; [ -n "$bad" ] && status="VULNERABLE"
  json_result "U-24" "파일 및 디렉터리 관리" "$status" "위험파일=[${bad}]" "root 소유, 타 사용자 쓰기 금지"
}

check_U25() {
  local n
  n=$(find / -xdev -type f -perm -0002 -not -path '/proc/*' -not -path '/tmp/*' -not -path '/var/tmp/*' -not -path '/dev/shm/*' 2>/dev/null | wc -l)
  status="GOOD"; [ "$n" -gt 0 ] && status="MANUAL"
  json_result "U-25" "파일 및 디렉터리 관리" "$status" "world_writable ${n}개" "world writable 파일 없음"
}

check_U26() {
  local n
  n=$(find /dev -xdev -type f 2>/dev/null | wc -l)
  status="GOOD"; [ "$n" -gt 0 ] && status="MANUAL"
  json_result "U-26" "파일 및 디렉터리 관리" "$status" "/dev 일반파일 ${n}개" "device 파일만 존재"
}

check_U27() {
  local n
  n=$(find /root /home -maxdepth 2 \( -name .rhosts -o -name hosts.equiv \) 2>/dev/null | wc -l)
  n=$((n + $( [ -f /etc/hosts.equiv ] && echo 1 || echo 0 )))
  status="GOOD"; [ "$n" -gt 0 ] && status="VULNERABLE"
  json_result "U-27" "파일 및 디렉터리 관리" "$status" ".rhosts/hosts.equiv ${n}개" "사용 금지(파일 없음/000)"
}

check_U28() {
  local active
  active=$(firewall-cmd --state 2>/dev/null)
  json_result "U-28" "파일 및 디렉터리 관리" "MANUAL" "firewalld=${active:-미확인}" "필요 IP/포트만 허용(수동 정책 확인 필요)"
}

check_U29() {
  local f="/etc/hosts.lpd" status="GOOD" current="파일 없음(N/A)"
  if [ -f "$f" ]; then
    local perm own; perm=$(perm_octal "$f"); own=$(owner_of "$f")
    current="owner=$own,perm=$perm"
    status="VULNERABLE"; [ "$own" == "root" ] && perm_le "$perm" 600 && status="GOOD"
  fi
  json_result "U-29" "파일 및 디렉터리 관리" "$status" "$current" "root:root, 600 이하"
}

check_U30() {
  local u status
  u=$(grep -REo 'umask [0-9]+' /etc/profile /etc/bashrc 2>/dev/null | head -1 | awk '{print $2}')
  u=${u:-000}
  status="VULNERABLE"
  [ "$u" -ge 022 ] 2>/dev/null && status="GOOD"
  json_result "U-30" "파일 및 디렉터리 관리" "$status" "umask=$u" "umask 022 이상"
}

check_U31() {
  local bad
  bad=$(awk -F: '$3>=1000 && $3!=65534 {print $6}' /etc/passwd | while read -r d; do
    [ -d "$d" ] || continue
    p=$(stat -c '%a' "$d"); [ "$p" -gt 750 ] 2>/dev/null && echo "$d:$p"
  done | paste -sd, -)
  status="GOOD"; [ -n "$bad" ] && status="VULNERABLE"
  json_result "U-31" "파일 및 디렉터리 관리" "$status" "위반=[${bad}]" "홈 디렉토리 750 이하, 본인 소유"
}

check_U32() {
  local bad
  bad=$(awk -F: '$3>=1000 && $3!=65534 {print $1":"$6}' /etc/passwd | while IFS=: read -r u d; do
    [ -d "$d" ] || echo "$u:$d"
  done | paste -sd, -)
  json_result "U-32" "파일 및 디렉터리 관리" "MANUAL" "홈디렉토리없음=[${bad}]" "지정된 홈 디렉토리가 실존해야 함"
}

check_U33() {
  local n
  n=$(find / -xdev -name '.*' -type f 2>/dev/null | wc -l)
  json_result "U-33" "파일 및 디렉터리 관리" "MANUAL" "숨김파일 ${n}개" "불필요 숨김파일/디렉토리 제거(수동 확인)"
}

# ===== 서비스 관리 (U-34~U-63) =====

check_svc_simple() {
  local id category svc title expected
  id="$1"; category="$2"; svc="$3"; title="$4"; expected="$5"
  local res status current
  res=$(svc_disabled_or_absent "$svc")
  status="${res%%:*}"; current="${res#*:}"
  json_result "$id" "$category" "$status" "$svc=$current" "$expected"
}

check_U34() { check_svc_simple "U-34" "서비스 관리" "finger" "Finger" "비활성화"; }
check_U35() {
  local val status
  val=$(grep -Ei '^\s*anonymous_enable' /etc/vsftpd/vsftpd.conf 2>/dev/null | tail -1 | awk -F= '{print $2}' | tr -d ' ')
  if [ ! -f /etc/vsftpd/vsftpd.conf ]; then status="GOOD"; val="not_installed"
  else status="VULNERABLE"; [[ "${val,,}" == "no" ]] && status="GOOD"; fi
  json_result "U-35" "서비스 관리" "$status" "anonymous_enable=$val" "익명 접근 금지(NO)"
}
check_U36() {
  local n
  n=0
  for s in rsh rlogin rexec; do svc_exists "$s" && (svc_active "$s" || svc_enabled "$s") && n=$((n+1)); done
  status="GOOD"; [ "$n" -gt 0 ] && status="VULNERABLE"
  json_result "U-36" "서비스 관리" "$status" "active_r_services=$n" "rsh/rlogin/rexec 비활성화"
}
check_U37() {
  local f="/etc/crontab" perm status="GOOD" current="파일 없음"
  if [ -f "$f" ]; then
    perm=$(perm_octal "$f"); current="perm=$perm"
    status="VULNERABLE"; perm_le "$perm" 640 && status="GOOD"
  fi
  json_result "U-37" "서비스 관리" "$status" "$current" "/etc/crontab 640 이하"
}
check_U38() {
  local n=0
  for s in echo discard daytime chargen; do svc_exists "$s" && (svc_active "$s" || svc_enabled "$s") && n=$((n+1)); done
  status="GOOD"; [ "$n" -gt 0 ] && status="VULNERABLE"
  json_result "U-38" "서비스 관리" "$status" "active_dos_services=$n" "echo/discard/daytime/chargen 비활성화"
}
check_U39() { check_svc_simple "U-39" "서비스 관리" "nfs-server" "NFS" "미사용시 비활성화"; }
check_U40() {
  local f="/etc/exports" current="파일 없음/N-A"
  [ -f "$f" ] && current=$(grep -v '^#' "$f" | grep -c .)
  json_result "U-40" "서비스 관리" "MANUAL" "exports_entries=$current" "everyone(*) 접근 금지(수동 확인)"
}
check_U41() { check_svc_simple "U-41" "서비스 관리" "autofs" "automount" "미사용시 비활성화"; }
check_U42() { check_svc_simple "U-42" "서비스 관리" "rpcbind" "RPC" "미사용시 비활성화"; }
check_U43() {
  local n=0
  for s in ypserv ypbind; do svc_exists "$s" && (svc_active "$s" || svc_enabled "$s") && n=$((n+1)); done
  status="GOOD"; [ "$n" -gt 0 ] && status="VULNERABLE"
  json_result "U-43" "서비스 관리" "$status" "active_nis_services=$n" "NIS/NIS+ 비활성화"
}
check_U44() {
  local n=0
  for s in tftp talk ntalk; do svc_exists "$s" && (svc_active "$s" || svc_enabled "$s") && n=$((n+1)); done
  status="GOOD"; [ "$n" -gt 0 ] && status="VULNERABLE"
  json_result "U-44" "서비스 관리" "$status" "active_services=$n" "tftp/talk 비활성화"
}
check_U45() {
  local ver="not_installed"
  command -v postconf &>/dev/null && ver=$(postconf mail_version 2>/dev/null)
  json_result "U-45" "서비스 관리" "MANUAL" "mail_version=$ver" "최신 패치 버전 사용(수동 확인)"
}
check_U46() {
  local status="GOOD" current="postfix 미설치(N/A)"
  if command -v postconf &>/dev/null; then
    local restrict; restrict=$(postconf -h smtpd_client_restrictions 2>/dev/null)
    current="smtpd_client_restrictions=$restrict"
    status="MANUAL"
  fi
  json_result "U-46" "서비스 관리" "$status" "$current" "일반 사용자 메일 릴레이 제한(수동 확인)"
}
check_U47() {
  local status="GOOD" current="postfix 미설치(N/A)"
  command -v postconf &>/dev/null && { current="smtpd_relay_restrictions=$(postconf -h smtpd_relay_restrictions 2>/dev/null)"; status="MANUAL"; }
  json_result "U-47" "서비스 관리" "$status" "$current" "오픈 릴레이 금지(수동 확인)"
}
check_U48() {
  local status="GOOD" current="postfix 미설치(N/A)"
  if command -v postconf &>/dev/null; then
    local v; v=$(postconf -h disable_vrfy_command 2>/dev/null)
    current="disable_vrfy_command=$v"
    status="VULNERABLE"; [[ "$v" == "yes" ]] && status="GOOD"
  fi
  json_result "U-48" "서비스 관리" "$status" "$current" "disable_vrfy_command=yes"
}
check_U49() {
  local status="GOOD" current="named 미설치(N/A)"
  command -v named &>/dev/null && { current="named -v: $(named -v 2>/dev/null)"; status="MANUAL"; }
  json_result "U-49" "서비스 관리" "$status" "$current" "최신 패치 버전 사용(수동 확인)"
}
check_U50() {
  local status="GOOD" current="named 미설치(N/A)"
  command -v named &>/dev/null && { status="MANUAL"; current="named.conf allow-transfer 확인 필요"; }
  json_result "U-50" "서비스 관리" "$status" "$current" "allow-transfer 제한(수동 확인)"
}
check_U51() {
  local status="GOOD" current="named 미설치(N/A)"
  command -v named &>/dev/null && { status="MANUAL"; current="named.conf allow-update 확인 필요"; }
  json_result "U-51" "서비스 관리" "$status" "$current" "동적 업데이트 제한(수동 확인)"
}
check_U52() { check_svc_simple "U-52" "서비스 관리" "telnet.socket" "Telnet" "비활성화(SSH 대체)"; }
check_U53() {
  local f="/etc/vsftpd/vsftpd.conf" status="GOOD" current="vsftpd 미설치(N/A)"
  if [ -f "$f" ]; then
    local banner; banner=$(grep -Ei '^\s*ftpd_banner' "$f" | tail -1)
    current="ftpd_banner_set=$( [ -n "$banner" ] && echo yes || echo no )"
    status="VULNERABLE"; [ -n "$banner" ] && status="GOOD"
  fi
  json_result "U-53" "서비스 관리" "$status" "$current" "배너에 버전정보 미노출"
}
check_U54() { check_svc_simple "U-54" "서비스 관리" "vsftpd" "FTP(평문)" "미사용시 비활성화, SFTP 권장(수동 판단)"; }
check_U55() {
  local shell status
  shell=$(getent passwd ftp | awk -F: '{print $7}')
  status="GOOD"; [ -z "$shell" ] && shell="계정없음(N/A)"
  [[ "$shell" == *nologin* || "$shell" == *false* || "$shell" == "계정없음(N/A)" ]] || status="VULNERABLE"
  json_result "U-55" "서비스 관리" "$status" "ftp_shell=$shell" "ftp 계정 쉘 nologin"
}
check_U56() {
  local f="/etc/vsftpd/ftpusers" status="GOOD" current="vsftpd 미설치(N/A)"
  [ -f /etc/vsftpd/vsftpd.conf ] && { status="MANUAL"; current="접근제어(user_list/tcp_wrappers) 확인 필요"; }
  json_result "U-56" "서비스 관리" "$status" "$current" "허용 IP/계정만 접속(수동 확인)"
}
check_U57() {
  local f status="GOOD" current="파일 없음(N/A)"
  for f in /etc/ftpusers /etc/vsftpd/ftpusers; do
    [ -f "$f" ] || continue
    current="root_in_$(basename "$f")=$(grep -qx root "$f" && echo yes || echo no)"
    status="VULNERABLE"; grep -qx root "$f" && status="GOOD"
  done
  json_result "U-57" "서비스 관리" "$status" "$current" "root 등 계정 ftp 접속 차단 목록에 포함"
}
check_U58() { check_svc_simple "U-58" "서비스 관리" "snmpd" "SNMP" "미사용시 비활성화"; }
check_U59() {
  local status="GOOD" current="snmpd 미설치(N/A)"
  svc_exists snmpd && { status="MANUAL"; current="SNMP 버전(v3 권장) 확인 필요"; }
  json_result "U-59" "서비스 관리" "$status" "$current" "SNMPv3 사용(수동 확인)"
}
check_U60() {
  local status="GOOD" current="snmpd 미설치(N/A)"
  svc_exists snmpd && { status="MANUAL"; current="/etc/snmp/snmpd.conf community 문자열 확인 필요"; }
  json_result "U-60" "서비스 관리" "$status" "$current" "public/private 등 기본값 금지(수동 확인)"
}
check_U61() {
  local status="GOOD" current="snmpd 미설치(N/A)"
  svc_exists snmpd && { status="MANUAL"; current="snmpd.conf 접근제어(ACL) 확인 필요"; }
  json_result "U-61" "서비스 관리" "$status" "$current" "허용 IP만 접근(수동 확인)"
}
check_U62() {
  local ok=1
  for f in /etc/motd /etc/issue /etc/issue.net; do [ -s "$f" ] || ok=0; done
  status="VULNERABLE"; [ "$ok" -eq 1 ] && status="GOOD"
  json_result "U-62" "서비스 관리" "$status" "motd/issue/issue.net 설정여부=$ok" "로그인 경고 배너 설정"
}
check_U63() {
  local perm status
  perm=$(perm_octal /etc/sudoers)
  status="MANUAL"
  json_result "U-63" "서비스 관리" "$status" "sudoers perm=$perm" "440 권한, 최소 권한 원칙(수동 확인)"
}

# ===== 패치 관리 (U-64) =====

check_U64() {
  local n
  n=$(dnf check-update --quiet 2>/dev/null | grep -c . )
  json_result "U-64" "패치 관리" "MANUAL" "적용가능업데이트 ${n}건" "정기 패치 적용(수동 확인)"
}

# ===== 로그 관리 (U-65~U-67) =====

check_U65() {
  local status="MANUAL" current="chronyd 미설치(N/A)"
  svc_exists chronyd && current="chronyd active=$(svc_active chronyd && echo yes || echo no)"
  json_result "U-65" "로그 관리" "$status" "$current" "NTP 동기화 구성(수동 확인)"
}
check_U66() {
  local status current
  if svc_active rsyslog; then status="GOOD"; current="rsyslog active"
  else status="VULNERABLE"; current="rsyslog inactive"; fi
  json_result "U-66" "로그 관리" "$status" "$current" "rsyslog 활성화 및 정책 로깅"
}
check_U67() {
  local d="/var/log" perm own status
  perm=$(perm_octal "$d"); own=$(owner_of "$d")
  status="VULNERABLE"
  [ "$own" == "root" ] && perm_le "$perm" 750 && status="GOOD"
  json_result "U-67" "로그 관리" "$status" "owner=$own,perm=$perm" "root 소유, 750 이하"
}
