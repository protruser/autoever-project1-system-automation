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
-- ---------------------------------------------------------
INSERT IGNORE INTO app_config (
    id,
    config_json
) VALUES (
    1,
    JSON_OBJECT(
        'ansiblePath', '/etc/ansible',
        'inventoryPath', '/etc/ansible/hosts',
        'playbookPath', '/opt/secureaudit/playbooks',
        'defaultUser', 'ansible',
        'sshKeyPath', '/etc/ansible/id_rsa',
        'sshPort', '22',
        'timeout', '30',
        'retries', '3',
        'notifyEmail', 'security@company.kr',
        'slackWebhook', '',
        'triggers', JSON_ARRAY(
            'scanComplete',
            'criticalFound',
            'remediationComplete',
            'remediationFailed'
        ),
        'security', JSON_OBJECT(
            'sessionTimeout', true,
            'lockout', true,
            'twoFactor', false,
            'auditLog', true
        )
    )
);
