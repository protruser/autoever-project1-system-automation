#!/usr/bin/env python3
"""02_generate_report.py - audit_reports/raw_json/*.json -> Excel 보고서

파일명에 _check_/_fix_ 가 있으면 조치 전/조치 후 보고서를 각각
report_before.xlsx / report_after.xlsx 로 나눠서 만든다.

사용법:
  python 02_generate_report.py
  python 02_generate_report.py --raw-dir audit_reports/raw_json --out-dir audit_reports

의존성: pip install openpyxl
"""
import argparse
import glob
import json
import os
from collections import Counter, defaultdict

from openpyxl import Workbook
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter

STATUS_FILL = {
    "FAIL": PatternFill("solid", fgColor="F8CBAD"),
    "GOOD": PatternFill("solid", fgColor="C6E0B4"),
    "CHECK": PatternFill("solid", fgColor="FFE699"),
    "NA": PatternFill("solid", fgColor="D9D9D9"),
    "ERR": PatternFill("solid", fgColor="D9D9D9"),
}
HEADER_FILL = PatternFill("solid", fgColor="305496")
HEADER_FONT = Font(color="FFFFFF", bold=True)


def load_results(raw_dir):
    """{name, analysis:[{IP,HOSTNAME,Timestamp,result:[{CheckID,status,...}]}]} 을
    엑셀 시트에서 다루기 쉬운 평탄한 행(row)들로 펼친다."""
    rows = []
    for path in sorted(glob.glob(os.path.join(raw_dir, "*.json"))):
        try:
            with open(path, encoding="utf-8") as f:
                data = json.load(f)
        except (json.JSONDecodeError, OSError) as e:
            print(f"[skip] {path}: {e}")
            continue
        for server in data.get("analysis", []):
            for item in server.get("result", []):
                rows.append({
                    "hostname": server.get("HOSTNAME", "unknown"),
                    "ip": server.get("IP", ""),
                    "timestamp": server.get("Timestamp", ""),
                    "check_id": item.get("CheckID", ""),
                    "status": item.get("status", "ERR"),
                    "current_value": item.get("Current_value", ""),
                    "expected_value": item.get("Expect_value", ""),
                    "os_type": item.get("OS_type", ""),
                    "os_spec": item.get("OS_spec", ""),
                    "_source_file": os.path.basename(path),
                })
    return rows


def style_header(ws, headers):
    for col, name in enumerate(headers, start=1):
        c = ws.cell(row=1, column=col, value=name)
        c.fill = HEADER_FILL
        c.font = HEADER_FONT
        c.alignment = Alignment(horizontal="center")
    ws.freeze_panes = "A2"


def autofit(ws, widths):
    for col, w in enumerate(widths, start=1):
        ws.column_dimensions[get_column_letter(col)].width = w


def build_summary_sheet(wb, rows):
    ws = wb.active
    ws.title = "요약"

    by_host = defaultdict(Counter)
    for r in rows:
        by_host[r.get("hostname", "unknown")][r.get("status", "ERR")] += 1

    total = Counter(r.get("status", "ERR") for r in rows)
    cols = ["GOOD", "FAIL", "NA", "CHECK", "ERR"]
    ws.append(["KISA U-01~U-67 진단 결과 요약"])
    ws["A1"].font = Font(size=14, bold=True)
    ws.append([])
    ws.append(["구분", *cols, "합계"])
    style_header(ws, ["구분", *cols, "합계"])

    ws.append(["전체", *[total[c] for c in cols], sum(total.values())])
    for host, c in sorted(by_host.items()):
        ws.append([host, *[c[k] for k in cols], sum(c.values())])

    fail_col = 2 + cols.index("FAIL")
    for row in ws.iter_rows(min_row=4, max_row=ws.max_row, min_col=fail_col, max_col=fail_col):
        for cell in row:
            if isinstance(cell.value, int) and cell.value > 0:
                cell.fill = STATUS_FILL["FAIL"]

    autofit(ws, [22, 10, 10, 10, 10, 10, 10])


def build_detail_sheet(wb, rows):
    ws = wb.create_sheet("상세")
    headers = ["hostname", "ip", "check_id", "status", "current_value",
               "expected_value", "os_type", "os_spec", "timestamp"]
    ws.append(headers)
    style_header(ws, headers)

    rows_sorted = sorted(rows, key=lambda r: (r.get("hostname", ""), r.get("check_id", "")))
    for r in rows_sorted:
        ws.append([r.get(h, "") for h in headers])
        status = r.get("status", "ERR")
        fill = STATUS_FILL.get(status)
        if fill:
            ws.cell(row=ws.max_row, column=headers.index("status") + 1).fill = fill

    autofit(ws, [18, 14, 10, 10, 40, 30, 10, 22, 20])


def build_manual_sheet(wb, rows):
    ws = wb.create_sheet("수동조치 필요")
    headers = ["hostname", "check_id", "current_value", "expected_value"]
    ws.append(headers)
    style_header(ws, headers)
    for r in sorted(rows, key=lambda r: (r.get("hostname", ""), r.get("check_id", ""))):
        if r.get("status") != "CHECK":
            continue
        ws.append([r.get(h, "") for h in headers])
    autofit(ws, [18, 10, 40, 30])


def build_report(rows, out_path):
    wb = Workbook()
    build_summary_sheet(wb, rows)
    build_detail_sheet(wb, rows)
    build_manual_sheet(wb, rows)
    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
    wb.save(out_path)
    print(f"[+] 보고서 생성 완료: {out_path} ({len(rows)}건)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw-dir", default="audit_reports/raw_json")
    ap.add_argument("--out-dir", default="audit_reports")
    args = ap.parse_args()

    rows = load_results(args.raw_dir)
    if not rows:
        print(f"[!] '{args.raw_dir}' 에서 진단 결과 JSON을 찾지 못했습니다.")
        return

    # 파일명에 _check_ / _fix_ 가 있으면(01_run_audit.yml 결과물) 조치 전/후로 나눠서
    # 보고서 2개를 만든다. 표시가 없으면(수동으로 만든 JSON 등) 하나로 합쳐 만든다.
    before = [r for r in rows if "_check_" in r["_source_file"]]
    after = [r for r in rows if "_fix_" in r["_source_file"]]
    other = [r for r in rows if r not in before and r not in after]

    if before or after:
        if before:
            build_report(before, os.path.join(args.out_dir, "report_before.xlsx"))
        if after:
            build_report(after, os.path.join(args.out_dir, "report_after.xlsx"))
        if other:
            build_report(other, os.path.join(args.out_dir, "report_other.xlsx"))
    else:
        build_report(rows, os.path.join(args.out_dir, "report.xlsx"))


if __name__ == "__main__":
    main()
