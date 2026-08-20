CREATE DATABASE IF NOT EXISTS `{DB_NAME}` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE `{DB_NAME}`;

CREATE TABLE IF NOT EXISTS audit_scans (
    id INT AUTO_INCREMENT PRIMARY KEY,
    scan_id VARCHAR(50) UNIQUE NOT NULL,
    project_name VARCHAR(100) NOT NULL,
    scan_date DATETIME NOT NULL,
    auditor VARCHAR(50) DEFAULT 'protruser',
    total_hosts INT DEFAULT 0,
    average_security_score DECIMAL(5,2) DEFAULT 0.00,
    total_grade VARCHAR(20) DEFAULT '양호',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS audit_hosts (
    id INT AUTO_INCREMENT PRIMARY KEY,
    scan_id VARCHAR(50) NOT NULL,
    hostname VARCHAR(100) NOT NULL,
    ip VARCHAR(45) NOT NULL,
    os VARCHAR(100),
    kernel VARCHAR(100),
    arch VARCHAR(50),
    total_checks INT DEFAULT 0,
    pass_count INT DEFAULT 0,
    vuln_count INT DEFAULT 0,
    na_count INT DEFAULT 0,
    compliance_rate VARCHAR(20),
    max_score INT DEFAULT 0,
    deducted_score INT DEFAULT 0,
    security_score_100 DECIMAL(5,2) DEFAULT 0.00,
    grade VARCHAR(20) DEFAULT '양호',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (scan_id) REFERENCES audit_scans(scan_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

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
    guide TEXT,
    remediation_cmd TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (host_id) REFERENCES audit_hosts(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
