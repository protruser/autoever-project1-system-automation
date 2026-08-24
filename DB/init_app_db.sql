-- =========================================================
-- SecureAudit 관리자 로그인 / 시스템 설정 DB 초기화 스크립트
-- =========================================================

CREATE DATABASE IF NOT EXISTS secureaudit_app
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE secureaudit_app;


-- ---------------------------------------------------------
-- 1. 관리자 계정 테이블
-- 회원가입 기능은 제공하지 않고, 관리자 계정만 사용한다.
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(64) NOT NULL UNIQUE,
    password_hash CHAR(64) NOT NULL,
    password_salt CHAR(32) NOT NULL,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    -- 설정 페이지 "로그인 실패 5회 시 계정 잠금"용
    failed_attempts INT UNSIGNED NOT NULL DEFAULT 0,
    locked_until DATETIME NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);


-- ---------------------------------------------------------
-- 2. 로그인 세션 테이블
-- 실제 토큰이 아니라 SHA-256 해시값만 저장한다.
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS auth_sessions (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT UNSIGNED NOT NULL,
    token_hash CHAR(64) NOT NULL UNIQUE,
    expires_at DATETIME NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_session_user
        FOREIGN KEY (user_id) REFERENCES users(id)
        ON DELETE CASCADE,

    INDEX idx_auth_sessions_expiry (expires_at)
);


-- ---------------------------------------------------------
-- 3. 시스템 설정 테이블
-- 관리자 1명 / 시스템 설정 1세트를 가정하므로 id=1 행만 사용한다.
-- 설정값은 하나의 JSON 문서로 저장한다.
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS app_config (
    id TINYINT UNSIGNED PRIMARY KEY,
    config_json JSON NOT NULL,
    updated_by BIGINT UNSIGNED NULL,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT fk_config_user
        FOREIGN KEY (updated_by) REFERENCES users(id)
        ON DELETE SET NULL
);


-- ---------------------------------------------------------
-- 3-1. 감사 로그 테이블
-- 설정 페이지 "감사 로그 저장" 체크박스가 켜져 있을 때, 조치(remediate) 작업을
-- 여기 기록한다.
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS audit_log (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT UNSIGNED NULL,
    action VARCHAR(64) NOT NULL,
    target VARCHAR(255) NULL,
    detail JSON NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_audit_log_user
        FOREIGN KEY (user_id) REFERENCES users(id)
        ON DELETE SET NULL,

    INDEX idx_audit_log_created (created_at)
);


-- ---------------------------------------------------------
-- 4. 초기 관리자 계정
-- ID: admin
-- PW: password
--
-- 비밀번호는 PBKDF2-HMAC-SHA256, 반복 100,000회로 해시화되어 있다.
-- 실제 배포 전 반드시 비밀번호를 변경해야 한다.
-- ---------------------------------------------------------
INSERT IGNORE INTO users (
    username,
    password_salt,
    password_hash
) VALUES (
    'admin',
    'secureaudit-demo',
    'b64081bea0c71cce5257718ffee4e13f342613983b707b04f7f68a918308d7a2'
);


-- ---------------------------------------------------------
-- 5. 초기 시스템 설정 JSON
--
-- ansiblePath/inventoryPath/playbookPath/defaultUser/sshKeyPath는 일부러
-- 빈 문자열로 시드한다. backend/ansible_ops.py의 conn_settings()가 빈 값을
-- "설정 페이지를 안 건드렸다"로 보고, 실제로 동작 중인 기본값(PATH의
-- ansible-playbook, 이 저장소의 Ansible/ 디렉터리, hosts.ini에 이미 있는 접속
-- 계정, 기본 SSH 설정)을 그대로 쓴다. 여기에 절대경로를 미리 박아두면 배포
-- 환경마다 다른 실제 경로와 어긋나서 진단/조치가 깨질 수 있다 - 관리자가
-- 설정 페이지에서 직접 다르게 지정했을 때만 값이 채워져야 한다.
-- ---------------------------------------------------------
INSERT IGNORE INTO app_config (
    id,
    config_json
) VALUES (
    1,
    JSON_OBJECT(
        'ansiblePath', '',
        'inventoryPath', '',
        'playbookPath', '',
        'defaultUser', '',
        'sshKeyPath', '',
        'sshPort', '22',
        'timeout', '30',
        'retries', '3',
        'slackWebhook', '',
        'triggers', JSON_ARRAY(
            'scanComplete',
            'criticalFound',
            'remediationComplete',
            'remediationFailed'
        ),
        'security', JSON_OBJECT(
            'lockout', true,
            'auditLog', true
        )
    )
);
