#!/usr/bin/env python3
"""
generate_report.py - 진단 결과 JSON들을 취합하여 단일 대시보드용 JSON 보고서 생성

사용법:
  python generate_report.py --raw-dir audit_reports/raw_json --out audit_reports/report.json
"""

import argparse
import glob
import json
import os
from datetime import datetime


def load_score_map(score_filepath="scores.json"):
    score_map = {}
    if not os.path.exists(score_filepath):
        print(f"[!] 점수 기준 파일({score_filepath})이 없습니다. 모든 배점이 0으로 처리됩니다.")
        return score_map

    try:
        with open(score_filepath, "r", encoding="utf-8") as f:
            score_data = json.load(f)
            if isinstance(score_data, list):
                for item in score_data:
                    code = item.get("code")
                    score = item.get("score", 0)
                    if code:
                        score_map[code] = score
            elif isinstance(score_data, dict):
                score_map = score_data
    except Exception as e:
        print(f"[!] 점수 파일 파싱 에러: {e}")

    return score_map


def process_host_file(filepath, score_map):
    try:
        with open(filepath, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        print(f"[!] {filepath} 읽기 실패: {e}")
        return None

    host_info = data.get("host_info", {})
    raw_results = data.get("results", [])

    summary = {
        "total": len(raw_results),
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

        # 상태값 통합 매핑
        raw_status = res.get("status", "검토").upper()
        if raw_status in ["양호", "GOOD"]:
            status = "양호"
        elif raw_status in ["취약", "FAIL", "VULNERABLE"]:
            status = "취약"
        elif raw_status in ["N/A", "NA", "ERROR"]:
            status = "N/A"
        else:
            status = "검토"

        weight = score_map.get(code, 0)
        risk = 0

        if status == "양호":
            summary["pass"] += 1
            summary["max_score"] += weight
        elif status == "취약":
            summary["vuln"] += 1
            summary["max_score"] += weight
            summary["deducted_score"] += weight
            risk = weight
        elif status == "N/A":
            summary["na"] += 1
        else:
            summary["manual"] += 1
            summary["max_score"] += weight

        res["weight_score"] = weight
        res["risk_score"] = risk
        res["status"] = status
        results.append(res)

    valid_total = summary["total"] - summary["na"]
    comp_rate = (summary["pass"] / valid_total * 100) if valid_total > 0 else 100
    summary["compliance_rate"] = f"{comp_rate:.1f}%"

    sec_score = (
        ((summary["max_score"] - summary["deducted_score"]) / summary["max_score"] * 100)
        if summary["max_score"] > 0
        else 100
    )
    summary["security_score_100"] = round(sec_score, 2)
    summary["security_score_ratio"] = round(sec_score / 100, 2)

    if sec_score >= 80:
        summary["grade"], summary["grade_color"] = "양호", "green"
    elif sec_score >= 60:
        summary["grade"], summary["grade_color"] = "취약", "orange"
    else:
        summary["grade"], summary["grade_color"] = "위험", "red"

    return {"host_info": host_info, "summary": summary, "results": results}


def main():
    ap = argparse.ArgumentParser(description="보안 진단 결과 통합 JSON 생성기")
    ap.add_argument("--raw-dir", default="audit_reports/raw_json", help="진단 결과 JSON 디렉토리")
    ap.add_argument("--out", default="audit_reports/report.json", help="저장될 종합 JSON 파일 경로")
    ap.add_argument("--score-file", default="scores.json", help="항목별 배점 기준 JSON 파일")
    args = ap.parse_args()

    score_map = load_score_map(args.score_file)
    host_files = sorted(glob.glob(os.path.join(args.raw_dir, "*.json")))

    if not host_files:
        print(f"[!] '{args.raw_dir}' 에서 진단 결과 JSON을 찾지 못했습니다.")
        return

    hosts_data = []
    total = {
        "hosts": 0,
        "checks": 0,
        "pass": 0,
        "vuln": 0,
        "na": 0,
        "max_score": 0,
        "deducted": 0,
    }

    for path in host_files:
        host_data = process_host_file(path, score_map)
        if host_data:
            hosts_data.append(host_data)
            total["hosts"] += 1
            total["checks"] += host_data["summary"]["total"]
            total["pass"] += host_data["summary"]["pass"]
            total["vuln"] += host_data["summary"]["vuln"]
            total["na"] += host_data["summary"]["na"]
            total["max_score"] += host_data["summary"]["max_score"]
            total["deducted"] += host_data["summary"]["deducted_score"]

    valid_checks = total["checks"] - total["na"]
    avg_comp = (total["pass"] / valid_checks * 100) if valid_checks > 0 else 100
    avg_sec = (
        ((total["max_score"] - total["deducted"]) / total["max_score"] * 100)
        if total["max_score"] > 0
        else 100
    )

    total_grade, total_color = "양호", "green"
    if avg_sec < 80:
        total_grade, total_color = "취약", "orange"
    if avg_sec < 60:
        total_grade, total_color = "위험", "red"

    final_report = {
        "scan_info": {
            "scan_id": f"SCAN-{datetime.now().strftime('%Y%m%d')}-01",
            "project_name": "주요정보통신기반시설 시스템 취약점 진단",
            "scan_date": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "auditor": "protruser",
        },
        "total_summary": {
            "total_hosts": total["hosts"],
            "total_checks": total["checks"],
            "total_pass": total["pass"],
            "total_vuln": total["vuln"],
            "total_na": total["na"],
            "average_compliance_rate": f"{avg_comp:.1f}%",
            "average_security_score": round(avg_sec, 2),
            "average_security_ratio": round(avg_sec / 100, 2),
            "total_grade": total_grade,
            "total_grade_color": total_color,
        },
        "hosts": hosts_data,
    }

    out_dir = os.path.dirname(args.out)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)

    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(final_report, f, ensure_ascii=False, indent=2)

    print(f"[+] 통합 JSON 생성 완료: {args.out} (총 {len(hosts_data)}대 취합)")


if __name__ == "__main__":
    main()