"""
KISA 취약점 점검 결과 -> 스타일이 적용된 다중 시트 XLSX 보고서 생성
기존 generate_csv()를 대체/보완하는 generate_xlsx() 제공

입력 데이터 형식 (기존 generate_csv와 동일한 hosts_data 사용, 필드 추가는 선택):
hosts_data = [
    {
        "hostname": "rocky1",
        "ip": "192.168.1.10",
        "os": "Rocky Linux 9.2",          # 선택, 없으면 "-"
        "owner": "보안관리자",             # 선택, 없으면 "-"
        "results": [
            {
                "code": "U-01",
                "category": "계정 관리",
                "title": "root 계정 원격 접속 제한",
                "importance": "상",          # 상/중/하
                "status": "취약",            # 양호/취약/검토(N/A)
                "action_result": "실패",      # 선택: 완료/실패/예외, 없으면 status로 추정
                "evidence_description": "...",   # 현재 설정 값 (상태와 무관하게 항상 표시)
                "recommendation_text": "...",    # 조치 내용 및 미조치시 사유
                "target_file": "/etc/ssh/sshd_config",  # 선택
            },
            ...
        ],
    },
    ...
]
"""

import io
from datetime import datetime

from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.utils import get_column_letter
from openpyxl.chart import DoughnutChart, Reference
from openpyxl.worksheet.worksheet import Worksheet

# ---------------------------------------------------------------------------
# 공통 스타일 정의 (첨부 예시 파일에서 추출한 값 그대로 사용)
# ---------------------------------------------------------------------------
NAVY = "1E293B"
LIGHT_GRAY = "F8FAFC"
BORDER_GRAY = "E2E8F0"

STATUS_STYLE = {
    "양호": {"fill": "DCFCE7", "font": "166534"},
    "취약": {"fill": "FEE2E2", "font": "991B1B"},
    "검토": {"fill": "E0F2FE", "font": "075985"},  # N/A / 예외 성격
}
IMPORTANCE_STYLE = {
    "상": {"fill": "FFE4E6", "font": "9F1239"},
    "중": {"fill": "FEF3C7", "font": "92400E"},
    "하": {"fill": "E0F2FE", "font": "075985"},
}
ACTION_FONT = {
    "완료": "166534",
    "실패": "991B1B",
    "예외": "075985",
}

thin = Side(style="thin", color=BORDER_GRAY)
BORDER_ALL = Border(left=thin, right=thin, top=thin, bottom=thin)

HEADER_FONT = Font(bold=True, size=9.5, color="FFFFFF")
HEADER_FILL = PatternFill("solid", fgColor=NAVY)
TITLE_FONT = Font(bold=True, size=20, color="0F172A")
SUBTITLE_FONT = Font(size=12, color="64748B")
LABEL_FONT = Font(bold=True, size=9, color="000000")
VALUE_FONT = Font(size=11, color="000000")
NAV_FONT = Font(size=9, color="0284C7", underline="single")
WRAP = Alignment(wrap_text=True, vertical="top")
CENTER = Alignment(horizontal="center", vertical="center")


def _status_key(raw_status: str) -> str:
    """다양한 표기(N/A, 예외, None 등)를 3분류로 정규화"""
    if not raw_status:
        return "검토"
    s = str(raw_status).strip()
    if s in ("양호", "OK", "GOOD", "PASS"):
        return "양호"
    if s in ("취약", "FAIL", "VULNERABLE"):
        return "취약"
    return "검토"  # N/A, 예외, 확인불가 등


def _action_result(status_key: str, given: str = None) -> str:
    if given:
        return given
    return {"양호": "완료", "취약": "실패", "검토": "예외"}[status_key]


def _score(status_key: str) -> int:
    return 10 if status_key == "양호" else 0


def _style_header_row(ws: Worksheet, row: int, ncols: int):
    for c in range(1, ncols + 1):
        cell = ws.cell(row=row, column=c)
        cell.fill = HEADER_FILL
        cell.font = HEADER_FONT
        cell.alignment = CENTER
        cell.border = BORDER_ALL


def _nav_link(ws: Worksheet, cell_ref: str, text: str, target_sheet: str):
    cell = ws[cell_ref]
    cell.value = text
    cell.font = NAV_FONT
    cell.hyperlink = f"#'{target_sheet}'!A1"


def _autofit(ws: Worksheet, widths: dict):
    for col, w in widths.items():
        ws.column_dimensions[col].width = w


# ---------------------------------------------------------------------------
# 데이터 집계
# ---------------------------------------------------------------------------
def _aggregate(hosts_data):
    """전체 통계, 중요도별 통계, 영역별 통계, 코드별 통계를 미리 계산"""
    total = {"양호": 0, "취약": 0, "검토": 0}
    by_importance = {}  # 상/중/하 -> {양호,취약,검토}
    by_category = {}  # 점검영역 -> {양호,취약,검토}
    by_code = {}  # code -> {category, title, importance, 전체, 취약, 취약서버}

    for h in hosts_data:
        hostname = h.get("hostname", "-")
        for r in h.get("results", []):
            sk = _status_key(r.get("status"))
            total[sk] += 1

            imp = r.get("importance", "중")
            by_importance.setdefault(imp, {"양호": 0, "취약": 0, "검토": 0})
            by_importance[imp][sk] += 1

            cat = r.get("category", "기타")
            by_category.setdefault(cat, {"양호": 0, "취약": 0, "검토": 0})
            by_category[cat][sk] += 1

            code = r.get("code", "-")
            entry = by_code.setdefault(
                code,
                {
                    "category": cat,
                    "title": r.get("title", ""),
                    "importance": imp,
                    "전체": 0,
                    "취약": 0,
                    "취약서버": [],
                },
            )
            entry["전체"] += 1
            if sk == "취약":
                entry["취약"] += 1
                entry["취약서버"].append(hostname)

    return total, by_importance, by_category, by_code


# ---------------------------------------------------------------------------
# 시트별 생성 함수
# ---------------------------------------------------------------------------
def _build_cover(wb: Workbook, meta: dict):
    ws = wb.create_sheet("표지")
    _nav_link(ws, "A1", ">> 대시보드", "대시보드")

    ws["B11"] = meta.get("title", "서버 취약점 진단 상세 결과 보고서")
    ws["B11"].font = TITLE_FONT
    ws.merge_cells("B11:H11")

    ws["B13"] = meta.get("subtitle", "UNIX 통합 보안 진단")
    ws["B13"].font = SUBTITLE_FONT
    ws.merge_cells("B13:H13")

    ws["B18"] = f"고객사: {meta.get('customer', '-')}"
    ws.merge_cells("B18:H18")
    ws["B20"] = f"진단 기간: {meta.get('period', '-')}"
    ws.merge_cells("B20:H20")
    ws["B22"] = f"대상 서버: {meta.get('host_count', 0)}대"
    ws.merge_cells("B22:H22")
    ws["B24"] = f"점검 항목: UNIX {meta.get('item_count', 0)}개"
    ws.merge_cells("B24:H24")

    for ref in ("B18", "B20", "B22", "B24"):
        ws[ref].font = Font(size=11, color="334155")

    _autofit(ws, {"A": 11, "B": 33, "C": 11, "D": 11, "E": 11, "F": 11, "G": 45, "H": 45})
    return ws


def _build_dashboard(wb: Workbook, total, by_importance, by_category):
    ws = wb.create_sheet("대시보드")
    _nav_link(ws, "A1", "<< 표지", "표지")

    # --- 전체 요약 ---
    ws["B10"] = "구분"
    ws["C10"] = "건수"
    _style_header_row(ws, 10, 0)
    for c, label in zip(("B10", "C10"), ("구분", "건수")):
        ws[c].fill = HEADER_FILL
        ws[c].font = HEADER_FONT
        ws[c].alignment = CENTER

    rows = [("양호", total["양호"]), ("취약", total["취약"]), ("검토", total["검토"])]
    for i, (label, val) in enumerate(rows, start=11):
        ws.cell(row=i, column=2, value=label)
        ws.cell(row=i, column=3, value=val)
        style = STATUS_STYLE.get(label, {})
        if style:
            ws.cell(row=i, column=2).fill = PatternFill("solid", fgColor=style["fill"])
            ws.cell(row=i, column=2).font = Font(color=style["font"], bold=True)

    # 도넛 차트
    chart = DoughnutChart()
    chart.title = "진단 결과 비율"
    data = Reference(ws, min_col=3, min_row=10, max_row=13)
    cats = Reference(ws, min_col=2, min_row=11, max_row=13)
    chart.add_data(data, titles_from_data=True)
    chart.set_categories(cats)
    chart.height = 7
    chart.width = 10
    ws.add_chart(chart, "E10")

    # --- 중요도별 진단 결과 ---
    r0 = 18
    ws.cell(row=r0, column=2, value="중요도별 진단 결과").font = Font(bold=True, size=11)
    headers = ["중요도", "양호", "취약", "검토", "양호율"]
    for i, hd in enumerate(headers):
        ws.cell(row=r0 + 1, column=2 + i, value=hd)
    _style_header_row(ws, r0 + 1, 0)
    for c in range(2, 7):
        cell = ws.cell(row=r0 + 1, column=c)
        cell.fill = HEADER_FILL
        cell.font = HEADER_FONT
        cell.alignment = CENTER

    row = r0 + 2
    for imp in ("상", "중", "하"):
        stat = by_importance.get(imp, {"양호": 0, "취약": 0, "검토": 0})
        tot = sum(stat.values())
        rate = f"{(stat['양호'] / tot * 100):.1f}%" if tot else "0.0%"
        vals = [imp, stat["양호"], stat["취약"], stat["검토"], rate]
        for c, v in enumerate(vals, start=2):
            cell = ws.cell(row=row, column=c, value=v)
            cell.border = BORDER_ALL
            cell.alignment = CENTER if c > 2 else Alignment(horizontal="left", vertical="center")
        row += 1

    # --- 점검 영역별 결과 ---
    r1 = row + 2
    ws.cell(row=r1, column=2, value="점검 영역별 결과").font = Font(bold=True, size=11)
    headers2 = ["점검 영역", "양호", "취약", "검토", "양호율"]
    for i, hd in enumerate(headers2):
        ws.cell(row=r1 + 1, column=2 + i, value=hd)
    _style_header_row(ws, r1 + 1, 0)
    for c in range(2, 7):
        cell = ws.cell(row=r1 + 1, column=c)
        cell.fill = HEADER_FILL
        cell.font = HEADER_FONT
        cell.alignment = CENTER

    row = r1 + 2
    for cat, stat in by_category.items():
        tot = sum(stat.values())
        rate = f"{(stat['양호'] / tot * 100):.1f}%" if tot else "0.0%"
        vals = [cat, stat["양호"], stat["취약"], stat["검토"], rate]
        for c, v in enumerate(vals, start=2):
            cell = ws.cell(row=row, column=c, value=v)
            cell.border = BORDER_ALL
            cell.alignment = CENTER if c > 2 else Alignment(horizontal="left", vertical="center")
        row += 1

    # 전체 요약 테이블에도 테두리
    for r in range(10, 14):
        for c in range(2, 4):
            ws.cell(row=r, column=c).border = BORDER_ALL

    _autofit(ws, {"A": 3, "B": 22, "C": 10, "D": 10, "E": 10, "F": 10})
    return ws


def _build_summary(wb: Workbook, by_code: dict):
    ws = wb.create_sheet("항목별 요약")
    _nav_link(ws, "A1", "<< 대시보드", "대시보드")
    ws["A2"] = f"UNIX 점검항목 ({len(by_code)}개)"
    ws["A2"].font = Font(bold=True, size=11)

    headers = ["No", "점검 영역", "코드", "항목명", "중요도", "전체", "취약", "양호율", "취약 서버 ID"]
    for i, hd in enumerate(headers, start=1):
        ws.cell(row=3, column=i, value=hd)
    _style_header_row(ws, 3, len(headers))

    for i, (code, e) in enumerate(sorted(by_code.items()), start=4):
        rate = f"{((e['전체'] - e['취약']) / e['전체'] * 100):.1f}%" if e["전체"] else "0.0%"
        vals = [
            i - 3,
            e["category"],
            code,
            e["title"],
            e["importance"],
            e["전체"],
            e["취약"],
            rate,
            ", ".join(e["취약서버"]) if e["취약서버"] else "-",
        ]
        for c, v in enumerate(vals, start=1):
            cell = ws.cell(row=i, column=c, value=v)
            cell.border = BORDER_ALL
        imp_style = IMPORTANCE_STYLE.get(e["importance"])
        if imp_style:
            cell = ws.cell(row=i, column=5)
            cell.fill = PatternFill("solid", fgColor=imp_style["fill"])
            cell.font = Font(color=imp_style["font"], bold=True)

    _autofit(ws, {"A": 6, "B": 15, "C": 8, "D": 37, "E": 8, "F": 8, "G": 8, "H": 10, "I": 20})
    return ws


def _build_host_sheet(wb: Workbook, host: dict):
    hostname = host.get("hostname", "unknown")
    ws = wb.create_sheet(hostname[:31])  # 시트명 31자 제한
    _nav_link(ws, "A1", "<< 대시보드", "대시보드")

    results = host.get("results", [])
    good = sum(1 for r in results if _status_key(r.get("status")) == "양호")
    total_cnt = len(results)
    score = round((good / total_cnt) * 100, 2) if total_cnt else 0.0

    info = [
        ("대상정보", "Hostname", host.get("hostname", "-"), "OS/DB", host.get("os", "-"), "보안점수", f"{score}점"),
        (None, "IP", host.get("ip", "-"), "담당자", host.get("owner", "-"), "양호/취약", f"{good}/{total_cnt}건"),
    ]
    for row_i, row_vals in enumerate(info, start=2):
        label0, k1, v1, k2, v2, k3, v3 = row_vals
        if label0:
            ws.cell(row=row_i, column=1, value=label0).font = Font(bold=True, size=10)
            ws.cell(row=row_i, column=1).fill = PatternFill("solid", fgColor=LIGHT_GRAY)
        ws.cell(row=row_i, column=2, value=k1).font = LABEL_FONT
        ws.cell(row=row_i, column=3, value=v1).font = VALUE_FONT
        ws.cell(row=row_i, column=5, value=k2).font = LABEL_FONT
        ws.cell(row=row_i, column=6, value=v2).font = VALUE_FONT
        ws.cell(row=row_i, column=8, value=k3).font = LABEL_FONT
        ws.cell(row=row_i, column=9, value=v3).font = Font(bold=True, size=10)

    headers = ["점검영역", "CODE", "점검항목", "위험도", "진단결과", "조치결과", "현재 설정", "조치 내용 및 미조치시 사유", "점수"]
    header_row = 6
    for i, hd in enumerate(headers, start=1):
        ws.cell(row=header_row, column=i, value=hd)
    _style_header_row(ws, header_row, len(headers))

    row = header_row + 1
    for r in results:
        sk = _status_key(r.get("status"))
        action = _action_result(sk, r.get("action_result"))
        score_val = _score(sk)
        if r.get("target_file"):
            prefix = f"[점검파일: {r['target_file']}]\n"
        else:
            prefix = ""
        current_setting = r.get("evidence_description")
        remediation = r.get("recommendation_text")
        vals = [
            r.get("category", "-"),
            r.get("code", "-"),
            r.get("title", "-"),
            r.get("importance", "-"),
            "검토" if sk == "검토" else sk,
            action,
            (prefix + current_setting) if current_setting else (prefix or None),
            remediation,
            score_val,
        ]
        for c, v in enumerate(vals, start=1):
            cell = ws.cell(row=row, column=c, value=v)
            cell.border = BORDER_ALL
            cell.alignment = WRAP

        imp_style = IMPORTANCE_STYLE.get(r.get("importance"))
        if imp_style:
            cell = ws.cell(row=row, column=4)
            cell.fill = PatternFill("solid", fgColor=imp_style["fill"])
            cell.font = Font(color=imp_style["font"], bold=True)

        st_style = STATUS_STYLE.get("검토" if sk == "검토" else sk)
        if st_style:
            cell = ws.cell(row=row, column=5)
            cell.fill = PatternFill("solid", fgColor=st_style["fill"])
            cell.font = Font(color=st_style["font"], bold=True)

        action_color = ACTION_FONT.get(action)
        if action_color:
            ws.cell(row=row, column=6).font = Font(color=action_color, bold=True)

        row += 1

    _autofit(ws, {"A": 15, "B": 11, "C": 37, "D": 22, "E": 11, "F": 18, "G": 45, "H": 45, "I": 11})
    ws.freeze_panes = "A7"
    return ws


# ---------------------------------------------------------------------------
# 외부 공개 함수
# ---------------------------------------------------------------------------
def generate_xlsx(hosts_data, meta: dict = None) -> bytes:
    """
    hosts_data: 기존 generate_csv()와 동일한 구조 (+선택적 os/owner/action_result 필드)
    meta: {"title":..., "subtitle":..., "customer":..., "period":...} 표지에 쓸 정보 (선택)
    반환: xlsx 파일의 바이트 (그대로 응답 body 나 파일로 저장)
    """
    meta = meta or {}
    total, by_importance, by_category, by_code = _aggregate(hosts_data)

    meta = {
        "title": meta.get("title", "서버 취약점 진단 상세 결과 보고서"),
        "subtitle": meta.get("subtitle", "UNIX 통합 보안 진단"),
        "customer": meta.get("customer", "-"),
        "period": meta.get("period", datetime.now().strftime("%Y-%m-%d")),
        "host_count": len(hosts_data),
        "item_count": len(by_code),
    }

    wb = Workbook()
    wb.remove(wb.active)  # 기본 빈 시트 제거

    _build_cover(wb, meta)
    _build_dashboard(wb, total, by_importance, by_category)
    _build_summary(wb, by_code)
    for h in hosts_data:
        _build_host_sheet(wb, h)

    output = io.BytesIO()
    wb.save(output)
    return output.getvalue()


# 기존 CSV 함수는 그대로 유지 (필요시 계속 사용 가능)
def generate_csv(hosts_data):
    import pandas as pd

    records = []
    for h in hosts_data:
        for r in h.get("results", []):
            records.append(
                {
                    "Hostname": h.get("hostname"),
                    "IP": h.get("ip"),
                    "Code": r.get("code"),
                    "Category": r.get("category"),
                    "Title": r.get("title"),
                    "Importance": r.get("importance"),
                    "Status": r.get("status"),
                    "Target_File": r.get("target_file"),
                    "Evidence": r.get("evidence_description"),
                    "Guide": r.get("recommendation_text"),
                }
            )
    df = pd.DataFrame(records)
    output = io.BytesIO()
    df.to_csv(output, index=False, encoding="utf-8-sig")
    return output.getvalue()
