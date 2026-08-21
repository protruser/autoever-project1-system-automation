#!/usr/bin/env python3
"""
02_generate_report.py - Raw JSON(리스트/딕셔너리 모두 지원)을 파싱하여 고시 기준 종합 리포트 생성
"""

import argparse
import glob
import json
import os
import sys
from datetime import datetime

DEFAULT_IMPORTANCE_SCORES = {
    "상": 10,
    "중": 8,
    "하": 6
}

def get_grade_info(score_ratio):
    if score_ratio >= 0.91:
        return "우수", "green"
    elif score_ratio >= 0.81:
        return "양호", "green"
    elif score_ratio >= 0.71:
        return "보통", "yellow"
    elif score_ratio >= 0.61:
        return "미흡", "orange"
    else:
        return "취약", "red"

def load_score_map(score_filepath="scores.json"):
    score_map = {}
    if not os.path.exists(score_filepath):
        return score_map
    try:
        with open(score_filepath, "r", encoding="utf-8") as f:
            data = json.load(f)
            if isinstance(data, list):
                for item in data:
                    if item.get("code"):
                        score_map[item["code"]] = item.get("score", 0)
            elif isinstance(data, dict):
                score_map = data
    except Exception as e:
        print(f"[!] 점수 파일 파싱 에러: {e}")
    return score_map

def process_host_file(filepath, score_map, category_stats):
    try:
        with open(filepath, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        print(f"[!] {filepath} JSON 로드 실패: {e}")
        return None

    # [핵심] 리스트 형태([])와 딕셔너리 형태({}) 모두 대응
    filename = os.path.splitext(os.path.basename(filepath))[0]
    if isinstance(data, list):
        raw_results = data
        host_info = {
            "hostname": filename,
            "ip": "192.168.1.10" if filename == "rocky1" else "192.168.1.20",
            "os": "Rocky Linux 9.2"
        }
    elif isinstance(data, dict):
        raw_results = data.get("results", [])
        host_info = data.get("host_info", {"hostname": filename, "ip": "0.0.0.0", "os": "Linux"})
    else:
        print(f"[!] {filepath}: 지원하지 않는 JSON 포맷입니다.")
        return None

    summary = {
        "pass": 0,
        "vuln": 0,
        "na": 0,
        "manual": 0,
        "max_score": 0,
        "deducted_score": 0,
    }

    results = []
    for res in raw_results:
        code = res.get("code", "UNKNOWN")
        category = res.get("category", "기타")
        importance = res.get("importance", "중")

        if category not in category_stats:
            category_stats[category] = {"total": 0, "pass": 0, "vuln": 0, "na": 0}
        category_stats[category]["total"] += 1

        raw_status = str(res.get("status", "검토")).upper()
        if any(w in raw_status for w in ["양호", "GOOD", "PASS"]):
            status = "양호"
            summary["pass"] += 1
            category_stats[category]["pass"] += 1
        elif any(w in raw_status for w in ["취약", "FAIL", "VULNERABLE"]):
            status = "취약"
            summary["vuln"] += 1
            category_stats[category]["vuln"] += 1
        elif any(w in raw_status for w in ["N/A", "NA", "해당없음", "해당 없음"]):
            status = "N/A"
            summary["na"] += 1
            category_stats[category]["na"] += 1
        else:
            status = "검토"
            summary["manual"] += 1

        weight = score_map.get(code, DEFAULT_IMPORTANCE_SCORES.get(importance, 8))
        risk = weight if status == "취약" else 0

        if status in ["양호", "취약", "검토"]:
            summary["max_score"] += weight
        if status == "취약":
            summary["deducted_score"] += weight

        res["code"] = code
        res["category"] = category
        res["importance"] = importance
        res["weight_score"] = weight
        res["risk_score"] = risk
        res["status"] = status
        
        if "guide" in res and "recommendation_text" not in res:
            res["recommendation_text"] = res.pop("guide")
        elif "recommendation_text" not in res:
            res["recommendation_text"] = ""

        if "ui_meta" not in res:
            res["ui_meta"] = {"reviewed": False, "fixed_by_user": False}

        results.append(res)

    A = summary["max_score"]
    B = summary["deducted_score"]
    sec_score = ((A - B) / A * 100) if A > 0 else 100.0

    ratio = round(sec_score / 100, 2)
    grade, _ = get_grade_info(ratio)

    host_summary = {
        "grade": grade,
        "security_score_100": round(sec_score, 2),
        "pass": summary["pass"],
        "vuln": summary["vuln"],
        "na": summary["na"]
    }

    return {"host_info": host_info, "summary": host_summary, "results": results}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw-dir", default="audit_reports/raw_json")
    ap.add_argument("--out", default="audit_reports/final_report.json")
    ap.add_argument("--score-file", default="scores.json")
    ap.add_argument("--client-code", default="autoever_2026")
    ap.add_argument("--client-name", default="현대오토에버")
    args = ap.parse_args()

    score_map = load_score_map(args.score_file)
    host_files = sorted(glob.glob(os.path.join(args.raw_dir, "*.json")))

    if not host_files:
        print(f"[!] '{args.raw_dir}' 에서 진단 결과 JSON을 찾지 못했습니다.")
        sys.exit(1)

    hosts_data = []
    category_stats = {}
    total = {"hosts": 0, "checks": 0, "pass": 0, "vuln": 0, "na": 0}

    for path in host_files:
        host_data = process_host_file(path, score_map, category_stats)
        if host_data:
            hosts_data.append(host_data)
            total["hosts"] += 1
            total["checks"] += len(host_data["results"])
            total["pass"] += host_data["summary"]["pass"]
            total["vuln"] += host_data["summary"]["vuln"]
            total["na"] += host_data["summary"]["na"]

    if not hosts_data:
        print("[!] 파싱된 호스트 결과가 없습니다.")
        sys.exit(1)

    avg_sec = sum(h["summary"]["security_score_100"] for h in hosts_data) / len(hosts_data)
    valid_checks = total["checks"] - total["na"]
    avg_comp = (total["pass"] / valid_checks * 100) if valid_checks > 0 else 100.0

    avg_ratio = round(avg_sec / 100, 2)
    total_grade, _ = get_grade_info(avg_ratio)

    now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    scan_id = f"SCAN-{datetime.now().strftime('%Y%m%d')}-01"

    final_report = {
        "client_info": {
            "client_code": args.client_code,
            "client_name": args.client_name,
            "db_name": f"audit_{args.client_code.lower().replace('-', '_')}",
            "report_generated_at": now_str
        },
        "scan_info": {
            "scan_id": scan_id,
            "project_name": "HIGHFIVE",
            "scan_date": now_str,
            "auditor": "protruser",
            "consultant_comment": "계정 및 파일 디렉터리 권한 관리 부분에 대한 조치가 시급합니다."
        },
        "total_summary": {
            "total_hosts": total["hosts"],
            "total_checks": total["checks"],
            "total_pass": total["pass"],
            "total_vuln": total["vuln"],
            "total_na": total["na"],
            "average_compliance_rate": f"{avg_comp:.1f}%",
            "average_security_score": round(avg_sec, 2),
            "average_security_ratio": avg_ratio,
            "total_grade": total_grade
        },
        "category_statistics": category_stats,
        "hosts": hosts_data
    }

    out_dir = os.path.dirname(args.out)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)

    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(final_report, f, ensure_ascii=False, indent=2)

    print(f"[+] 최종 JSON 취합 완료: {args.out} (총 {len(hosts_data)}대 호스트 반영)")

if __name__ == "__main__":
    main()
