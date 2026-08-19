#!/usr/bin/env python3
"""02_generate_report.py - audit_reports/raw_json/*.json -> Excel 보고서

사용법:
  python 02_generate_report.py
  python 02_generate_report.py --raw-dir audit_reports/raw_json --out audit_reports/report.xlsx

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
    "VULNERABLE": PatternFill("solid", fgColor="F8CBAD"),
    "GOOD": PatternFill("solid", fgColor="C6E0B4"),
    "MANUAL": PatternFill("solid", fgColor="FFE699"),
    "ERROR": PatternFill("solid", fgColor="D9D9D9"),
}
HEADER_FILL = PatternFill("solid", fgColor="305496")
HEADER_FONT = Font(color="FFFFFF", bold=True)


def load_results(raw_dir):
    rows = []
    for path in sorted(glob.glob(os.path.join(raw_dir, "*.json"))):
        try:
            with open(path, encoding="utf-8") as f:
                data = json.load(f)
        except (json.JSONDecodeError, OSError) as e:
            print(f"[skip] {path}: {e}")
            continue
        if isinstance(data, dict):
            data = [data]
        for item in data:
            item["_source_file"] = os.path.basename(path)
            rows.append(item)
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
        by_host[r.get("hostname", "unknown")][r.get("status", "ERROR")] += 1

    total = Counter(r.get("status", "ERROR") for r in rows)
    ws.append(["KISA U-01~U-67 진단 결과 요약"])
    ws["A1"].font = Font(size=14, bold=True)
    ws.append([])
    ws.append(["구분", "GOOD", "VULNERABLE", "MANUAL", "ERROR", "합계"])
    style_header(ws, ["구분", "GOOD", "VULNERABLE", "MANUAL", "ERROR", "합계"])

    ws.append(["전체", total["GOOD"], total["VULNERABLE"], total["MANUAL"], total["ERROR"], sum(total.values())])
    for host, c in sorted(by_host.items()):
        ws.append([host, c["GOOD"], c["VULNERABLE"], c["MANUAL"], c["ERROR"], sum(c.values())])

    for row in ws.iter_rows(min_row=4, max_row=ws.max_row, min_col=3, max_col=3):
        for cell in row:
            if isinstance(cell.value, int) and cell.value > 0:
                cell.fill = STATUS_FILL["VULNERABLE"]

    autofit(ws, [22, 10, 12, 10, 10, 10])


def build_detail_sheet(wb, rows):
    ws = wb.create_sheet("상세")
    headers = ["hostname", "check_id", "category", "status", "current_value",
               "expected_value", "os_type", "os_version", "timestamp"]
    ws.append(headers)
    style_header(ws, headers)

    rows_sorted = sorted(rows, key=lambda r: (r.get("hostname", ""), r.get("check_id", "")))
    for r in rows_sorted:
        ws.append([r.get(h, "") for h in headers])
        status = r.get("status", "ERROR")
        fill = STATUS_FILL.get(status)
        if fill:
            ws.cell(row=ws.max_row, column=headers.index("status") + 1).fill = fill

    autofit(ws, [18, 10, 20, 12, 40, 30, 10, 12, 20])


def build_manual_sheet(wb, rows):
    ws = wb.create_sheet("수동조치 필요")
    headers = ["hostname", "check_id", "category", "current_value", "expected_value"]
    ws.append(headers)
    style_header(ws, headers)
    for r in sorted(rows, key=lambda r: (r.get("hostname", ""), r.get("check_id", ""))):
        if r.get("status") != "MANUAL":
            continue
        ws.append([r.get(h, "") for h in headers])
    autofit(ws, [18, 10, 20, 40, 30])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw-dir", default="audit_reports/raw_json")
    ap.add_argument("--out", default="audit_reports/report.xlsx")
    args = ap.parse_args()

    rows = load_results(args.raw_dir)
    if not rows:
        print(f"[!] '{args.raw_dir}' 에서 진단 결과 JSON을 찾지 못했습니다.")
        return

    wb = Workbook()
    build_summary_sheet(wb, rows)
    build_detail_sheet(wb, rows)
    build_manual_sheet(wb, rows)

    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
    wb.save(args.out)
    print(f"[+] 보고서 생성 완료: {args.out} ({len(rows)}건)")


if __name__ == "__main__":
    main()
