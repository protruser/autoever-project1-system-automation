CREATE DATABASE IF NOT EXISTS `{DB_NAME}` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE `{DB_NAME}`;

-- 1. 스캔 회차 테이블
CREATE TABLE IF NOT EXISTS audit_scans (
    id INT AUTO_INCREMENT PRIMARY KEY,
    scan_id VARCHAR(50) UNIQUE NOT NULL,
    project_name VARCHAR(100) NOT NULL,
    scan_date DATETIME NOT NULL,
    auditor VARCHAR(50) DEFAULT 'protruser',
    consultant_comment TEXT,
    total_hosts INT DEFAULT 0,
    total_checks INT DEFAULT 0,
    total_pass INT DEFAULT 0,
    total_vuln INT DEFAULT 0,
    total_na INT DEFAULT 0,
    average_compliance_rate VARCHAR(20),
    average_security_score DECIMAL(5,2) DEFAULT 0.00,
    average_security_ratio DECIMAL(4,2) DEFAULT 0.00,
    total_grade VARCHAR(20) DEFAULT '양호',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 2. 점검 대상 호스트 테이블
CREATE TABLE IF NOT EXISTS audit_hosts (
    id INT AUTO_INCREMENT PRIMARY KEY,
    scan_id VARCHAR(50) NOT NULL,
    hostname VARCHAR(100) NOT NULL,
    ip VARCHAR(45) NOT NULL,
    os VARCHAR(100),
    -- "초기 설정" 시점에 gather_facts가 systemctl로 감지한 DB 엔진 힌트
    -- ("mysql"/"postgresql"/"mysql,postgresql"/""). 기존 DB에는
    -- backend/db.py::ensure_hosts_extended_schema()가 기동 시 자동으로 추가한다.
    detected_db VARCHAR(50) NOT NULL DEFAULT '',
    pass_count INT DEFAULT 0,
    vuln_count INT DEFAULT 0,
    na_count INT DEFAULT 0,
    security_score_100 DECIMAL(5,2) DEFAULT 0.00,
    grade VARCHAR(20) DEFAULT '양호',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (scan_id) REFERENCES audit_scans(scan_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 2-1. 호스트 사실 정보 영구 보관 테이블 (스캔 회차와 무관)
-- audit_hosts는 스캔마다 지우고 다시 만드는 테이블이라, detected_db 같은
-- "초기 설정" 시점 정보를 거기에만 두면 스캔 이력이 한 번만 끊겨도 영구히
-- 사라지는 문제가 있다(실측됨). 호스트명당 1행만 여기 영구 보관하고,
-- 03_save_to_mysql.py가 매 스캔마다 이 값을 audit_hosts로 이어붙인다.
CREATE TABLE IF NOT EXISTS host_facts (
    hostname VARCHAR(100) PRIMARY KEY,
    os VARCHAR(100),
    detected_db VARCHAR(50) NOT NULL DEFAULT '',
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 3. 세부 점검 결과 테이블
CREATE TABLE IF NOT EXISTS audit_results (
    id INT AUTO_INCREMENT PRIMARY KEY,
    host_id INT NOT NULL,
    code VARCHAR(20) NOT NULL,
    category VARCHAR(50),
    title VARCHAR(255),
    importance VARCHAR(10),
    weight_score INT DEFAULT 0,
    risk_score INT DEFAULT 0,
    status VARCHAR(20) NOT NULL,
    target_file VARCHAR(255),
    command TEXT,
    command_output TEXT,
    evidence_description TEXT,
    recommendation_text TEXT,
    remediation_cmd TEXT,
    reviewed BOOLEAN DEFAULT FALSE,
    fixed_by_user BOOLEAN DEFAULT FALSE,
    manual_verdict VARCHAR(10) NOT NULL DEFAULT '',
    manual_reason TEXT,
    manual_by BIGINT UNSIGNED NULL,
    manual_at DATETIME NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (host_id) REFERENCES audit_hosts(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
