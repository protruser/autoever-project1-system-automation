#!/bin/bash
# fixes.sh - items.sh에서 자동조치(1)로 표시된 항목의 조치(fix) 함수.
# 모든 함수는 변경 전 backup_file()로 원본을 백업한 뒤 '최소한의 변경'만 수행한다.

fix_U01() {
  local f="/etc/ssh/sshd_config"
  backup_file "$f"
  if grep -Eqi '^\s*PermitRootLogin' "$f"; then
    sed -i -E 's/^[[:space:]]*#?[[:space:]]*PermitRootLogin.*/PermitRootLogin no/I' "$f"
  else
    echo "PermitRootLogin no" >> "$f"
  fi
  systemctl restart sshd 2>/dev/null
}

fix_U02() {
  backup_file /etc/login.defs
  backup_file /etc/security/pwquality.conf
  grep -q '^PASS_MAX_DAYS' /etc/login.defs && sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   90/' /etc/login.defs || echo "PASS_MAX_DAYS   90" >> /etc/login.defs
  if [ -f /etc/security/pwquality.conf ]; then
    grep -q '^minlen' /etc/security/pwquality.conf && sed -i 's/^minlen.*/minlen = 8/' /etc/security/pwquality.conf || echo "minlen = 8" >> /etc/security/pwquality.conf
  fi
}

fix_U03() {
  local f="/etc/security/faillock.conf"
  backup_file "$f"
  grep -q '^deny =' "$f" 2>/dev/null && sed -i 's/^deny =.*/deny = 5/' "$f" || echo "deny = 5" >> "$f"
}

fix_U04() {
  pwconv 2>/dev/null
}

fix_U06() {
  local f="/etc/pam.d/su"
  backup_file "$f"
  grep -q 'pam_wheel.so' "$f" || sed -i '/pam_rootok.so/a auth            required        pam_wheel.so use_uid' "$f"
}

fix_U12() {
  local f="/etc/profile.d/tmout.sh"
  echo 'TMOUT=600' > "$f"
  echo 'readonly TMOUT' >> "$f"
  echo 'export TMOUT' >> "$f"
  chmod 644 "$f"
}

fix_U13() {
  backup_file /etc/login.defs
  grep -q '^ENCRYPT_METHOD' /etc/login.defs && sed -i 's/^ENCRYPT_METHOD.*/ENCRYPT_METHOD SHA512/' /etc/login.defs || echo "ENCRYPT_METHOD SHA512" >> /etc/login.defs
}

fix_U14() {
  chmod 750 /root
}

fix_U16() { chown root:root /etc/passwd; chmod 644 /etc/passwd; }
fix_U17() {
  find /etc/rc.d/init.d /usr/lib/systemd/system -maxdepth 1 -type f ! -user root -exec chown root {} \; 2>/dev/null
  find /etc/rc.d/init.d /usr/lib/systemd/system -maxdepth 1 -type f -perm /go+w -exec chmod go-w {} \; 2>/dev/null
}

fix_U18() { chown root:root /etc/shadow; chmod 400 /etc/shadow; }
fix_U19() { chown root:root /etc/hosts; chmod 644 /etc/hosts; }
fix_U20() {
  for f in /etc/xinetd.conf /etc/inetd.conf; do
    [ -f "$f" ] || continue
    backup_file "$f"; chown root:root "$f"; chmod 600 "$f"
  done
}
fix_U21() {
  for f in /etc/rsyslog.conf /etc/syslog.conf; do
    [ -f "$f" ] || continue
    backup_file "$f"; chown root:root "$f"; chmod 644 "$f"
  done
}
fix_U22() { chown root:root /etc/services; chmod 644 /etc/services; }
fix_U24() {
  for f in /etc/profile /etc/bashrc /etc/profile.d/*; do
    [ -f "$f" ] || continue
    chown root:root "$f" 2>/dev/null
    chmod o-w "$f" 2>/dev/null
  done
}
fix_U27() {
  local f
  for f in /root/.rhosts /root/.rhosts.equiv /etc/hosts.equiv; do
    [ -f "$f" ] && { backup_file "$f"; rm -f "$f"; }
  done
  find /home -maxdepth 2 -name .rhosts 2>/dev/null | while read -r rf; do backup_file "$rf"; rm -f "$rf"; done
}
fix_U29() {
  local f="/etc/hosts.lpd"
  [ -f "$f" ] && { backup_file "$f"; chown root:root "$f"; chmod 600 "$f"; }
}
fix_U30() {
  for f in /etc/profile /etc/bashrc; do
    backup_file "$f"
    grep -q '^umask' "$f" && sed -i 's/^umask.*/umask 022/' "$f" || echo "umask 022" >> "$f"
  done
}
fix_U31() {
  awk -F: '$3>=1000 && $3!=65534 {print $6}' /etc/passwd | while read -r d; do
    [ -d "$d" ] || continue
    chmod 750 "$d" 2>/dev/null
  done
}

fix_U34() { svc_disable_now finger; }
fix_U35() {
  local f="/etc/vsftpd/vsftpd.conf"
  [ -f "$f" ] || return 0
  backup_file "$f"
  grep -qi '^\s*anonymous_enable' "$f" && sed -i -E 's/^[[:space:]]*anonymous_enable=.*/anonymous_enable=NO/I' "$f" || echo "anonymous_enable=NO" >> "$f"
  systemctl restart vsftpd 2>/dev/null
}
fix_U36() { for s in rsh rlogin rexec; do svc_disable_now "$s"; done; }
fix_U37() { [ -f /etc/crontab ] && { backup_file /etc/crontab; chmod 640 /etc/crontab; }; }
fix_U38() { for s in echo discard daytime chargen echo-udp discard-udp daytime-udp chargen-udp; do svc_disable_now "$s"; done; }
fix_U39() { svc_disable_now nfs-server; }
fix_U41() { svc_disable_now autofs; }
fix_U42() { svc_disable_now rpcbind; }
fix_U43() { svc_disable_now ypserv; svc_disable_now ypbind; }
fix_U44() { for s in tftp talk ntalk; do svc_disable_now "$s"; done; }
fix_U48() {
  command -v postconf &>/dev/null || return 0
  postconf -e "disable_vrfy_command=yes" 2>/dev/null
  systemctl reload postfix 2>/dev/null
}
fix_U52() { svc_disable_now telnet.socket; }
fix_U53() {
  local f="/etc/vsftpd/vsftpd.conf"
  [ -f "$f" ] || return 0
  backup_file "$f"
  grep -qi '^\s*ftpd_banner' "$f" || echo 'ftpd_banner=Authorized access only.' >> "$f"
  systemctl restart vsftpd 2>/dev/null
}
fix_U55() { getent passwd ftp &>/dev/null && usermod -s /sbin/nologin ftp; }
fix_U57() {
  for f in /etc/ftpusers /etc/vsftpd/ftpusers; do
    [ -f "$f" ] || continue
    backup_file "$f"
    grep -qx root "$f" || echo root >> "$f"
  done
}
fix_U58() { svc_disable_now snmpd; }
fix_U62() {
  local msg="Authorized users only. All activity may be monitored and reported."
  for f in /etc/motd /etc/issue /etc/issue.net; do
    backup_file "$f"
    echo "$msg" > "$f"
  done
}
fix_U66() { systemctl enable --now rsyslog 2>/dev/null; }
fix_U67() { chown root:root /var/log; chmod 750 /var/log; }
