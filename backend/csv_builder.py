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
from zoneinfo import ZoneInfo

from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.utils import get_column_letter
from openpyxl.chart import DoughnutChart, Reference
from openpyxl.worksheet.worksheet import Worksheet

# 서버(컨트롤 노드)의 시스템 타임존은 UTC라서 datetime.now()가 UTC 벽시계를 반환한다.
# 보고서 표지에 찍히는 기간/생성일은 KST로 명시해서 기록한다.
KST = ZoneInfo("Asia/Seoul")

# ---------------------------------------------------------------------------
# 공통 스타일 정의 (첨부 예시 파일에서 추출한 값 그대로 사용)
# ---------------------------------------------------------------------------
NAVY = "1E293B"
LIGHT_GRAY = "F8FAFC"
BORDER_GRAY = "E2E8F0"

STATUS_STYLE = {
    "양호": {"fill": "DCFCE7", "font": "166534"},
    "취약": {"fill": "FEE2E2", "font": "991B1B"},
    "검토": {"fill": "E0F2FE", "font": "075985"},
    "N/A": {"fill": "F1F5F9", "font": "475569"},
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
    """DB 상태를 양호/취약/검토/N/A 네 가지로 정규화한다."""
    if raw_status is None or str(raw_status).strip() == "":
        return "검토"
    value = str(raw_status).strip().upper()
    if value in ("양호", "OK", "GOOD", "PASS"):
        return "양호"
    if value in ("취약", "FAIL", "VULNERABLE"):
        return "취약"
    if value in ("N/A", "NA", "NOT APPLICABLE", "해당없음"):
        return "N/A"
    return "검토"


def _action_status(result: dict, status_key: str) -> str:
    """진단 판정과 실제 조치 상태를 혼동하지 않도록 별도로 표시한다."""
    if result.get("fixed_by_user"):
        return "조치 완료"
    if result.get("manual_verdict"):
        return "수동 판정"
    if status_key == "취약":
        return "미조치"
    if status_key == "검토":
        return "검토 필요"
    return "조치 불필요"  # 양호 / N/A


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
    total = {"양호": 0, "취약": 0, "검토": 0, "N/A": 0}
    by_importance = {}  # 상/중/하 -> 상태별 건수
    by_category = {}  # 점검영역 -> 상태별 건수
    by_code = {}  # code -> {category, title, importance, 전체, 취약, 취약서버}

    for h in hosts_data:
        hostname = h.get("hostname", "-")
        for r in h.get("results", []):
            sk = _status_key(r.get("status"))
            total[sk] += 1

            imp = r.get("importance", "중")
            by_importance.setdefault(imp, {"양호": 0, "취약": 0, "검토": 0, "N/A": 0})
            by_importance[imp][sk] += 1

            cat = r.get("category", "기타")
            by_category.setdefault(cat, {"양호": 0, "취약": 0, "검토": 0, "N/A": 0})
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


def _build_dashboard(wb: Workbook, hosts_data, total, by_importance, by_category, by_code):
    ws = wb.create_sheet("대시보드")
    _nav_link(ws, "A1", "<< 표지", "표지")

    # 핵심 카드: 열자마자 우선 조치 대상을 인지하도록 배치
    host_scores = []
    for h in hosts_data:
        results = h.get("results", [])
        good = sum(_status_key(r.get("status")) == "양호" for r in results)
        score = round((good / len(results)) * 100, 2) if results else 0
        host_scores.append((score, h.get("hostname", "-"), h.get("ip", "-")))
    critical = sum(1 for h in hosts_data for r in h.get("results", []) if _status_key(r.get("status")) == "취약" and r.get("importance") == "상")
    cards = [("대상 서버", f"{len(hosts_data)}대"), ("취약 항목", f"{total['취약']}건"), ("상 위험 취약", f"{critical}건"), ("검토 필요", f"{total['검토']}건")]
    for col, (label, value) in zip((2, 3, 4, 5), cards):
        a = ws.cell(3, col, label); b = ws.cell(4, col, value)
        for cell in (a, b):
            cell.fill = PatternFill("solid", fgColor=NAVY); cell.alignment = CENTER; cell.border = BORDER_ALL
        a.font = Font(size=9, color="CBD5E1", bold=True); b.font = Font(size=16, color="FFFFFF", bold=True)
    ws.merge_cells("B6:E6"); ws["B6"] = "우선순위: 상 위험 취약점 → 보안 점수 하위 서버 → 반복 취약점 순으로 조치하세요."
    ws["B6"].font = Font(size=9, color="475569", italic=True)

    # 전체 결과 + 도넛 차트
    for c, label in zip(("B10", "C10"), ("구분", "건수")):
        ws[c] = label; ws[c].fill = HEADER_FILL; ws[c].font = HEADER_FONT; ws[c].alignment = CENTER; ws[c].border = BORDER_ALL
    for i, label in enumerate(("양호", "취약", "검토", "N/A"), start=11):
        ws.cell(i, 2, label); ws.cell(i, 3, total[label])
        style = STATUS_STYLE[label]
        ws.cell(i, 2).fill = PatternFill("solid", fgColor=style["fill"]); ws.cell(i, 2).font = Font(color=style["font"], bold=True)
        for c in (2,3): ws.cell(i,c).border = BORDER_ALL; ws.cell(i,c).alignment = CENTER
    chart = DoughnutChart(); chart.title = "진단 결과 비율"
    chart.add_data(Reference(ws, min_col=3, min_row=10, max_row=14), titles_from_data=True)
    chart.set_categories(Reference(ws, min_col=2, min_row=11, max_row=14)); chart.height = 7; chart.width = 10; ws.add_chart(chart, "E10")

    # 점수 하위 서버
    ws["B17"] = "보안 점수 하위 서버"; ws["B17"].font = Font(bold=True, size=11)
    for c, label in enumerate(("순위", "서버", "IP", "점수"), start=2):
        cell=ws.cell(18,c,label); cell.fill=HEADER_FILL; cell.font=HEADER_FONT; cell.alignment=CENTER; cell.border=BORDER_ALL
    for i, (score, name, ip) in enumerate(sorted(host_scores)[:5], start=19):
        for c,v in enumerate((i-18,name,ip,f"{score:.2f}점"), start=2):
            cell=ws.cell(i,c,v); cell.border=BORDER_ALL; cell.alignment=CENTER if c in (2,5) else Alignment(vertical="center")
            if c == 5 and score < 60: cell.font=Font(color="991B1B",bold=True)

    # 반복 취약점 Top 5
    start_row = 26
    ws.cell(start_row,2,"반복 취약점 Top 5").font=Font(bold=True,size=11)
    for c,label in enumerate(("코드","항목명","취약 서버","영향 범위"),start=2):
        cell=ws.cell(start_row+1,c,label); cell.fill=HEADER_FILL; cell.font=HEADER_FONT; cell.alignment=CENTER; cell.border=BORDER_ALL
    repeated=sorted(((e["취약"],code,e) for code,e in by_code.items() if e["취약"]), reverse=True)[:5]
    for row,(count,code,e) in enumerate(repeated,start=start_row+2):
        vals=(code,e["title"],", ".join(e["취약서버"]),f"{count}대")
        for c,v in enumerate(vals,start=2):
            cell=ws.cell(row,c,v); cell.border=BORDER_ALL; cell.alignment=WRAP if c in (3,4) else CENTER

    _autofit(ws,{"A":3,"B":14,"C":30,"D":25,"E":12,"F":10,"G":10})
    return ws


def _build_summary(wb: Workbook, by_code: dict):
    ws = wb.create_sheet("항목별 요약")
    _nav_link(ws, "A1", "<< 대시보드", "대시보드")
    ws["A2"] = f"UNIX 점검항목 ({len(by_code)}개)"
    ws["A2"].font = Font(bold=True, size=11)

    headers = ["No", "점검 영역", "코드", "항목명", "중요도", "전체", "취약", "취약률", "취약 서버 ID"]
    for i, hd in enumerate(headers, start=1):
        ws.cell(row=3, column=i, value=hd)
    _style_header_row(ws, 3, len(headers))

    for i, (code, e) in enumerate(sorted(by_code.items()), start=4):
        rate = f"{(e['취약'] / e['전체'] * 100):.1f}%" if e["전체"] else "0.0%"
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
    ws = wb.create_sheet(hostname[:31])
    _nav_link(ws, "A1", "<< 대시보드", "대시보드")
    _nav_link(ws, "C1", "<< 항목별 요약", "항목별 요약")
    results = host.get("results", [])
    counts = {key: sum(_status_key(r.get("status")) == key for r in results) for key in ("양호","취약","검토","N/A")}
    total_cnt = len(results); score = round((counts["양호"] / total_cnt) * 100, 2) if total_cnt else 0.0
    info = [("대상정보", "Hostname", host.get("hostname", "-"), "OS/DB", host.get("os", "-"), "보안점수", f"{score}점"),
            (None, "IP", host.get("ip", "-"), "담당자", host.get("owner", "-"), "판정 현황", f"양호 {counts['양호']} · 취약 {counts['취약']} · 검토 {counts['검토']} · N/A {counts['N/A']}")]
    for row_i, row_vals in enumerate(info, start=2):
        label0,k1,v1,k2,v2,k3,v3=row_vals
        if label0: ws.cell(row_i,1,label0).font=Font(bold=True,size=10); ws.cell(row_i,1).fill=PatternFill("solid",fgColor=LIGHT_GRAY)
        for col,value,is_label in ((2,k1,True),(3,v1,False),(5,k2,True),(6,v2,False),(8,k3,True),(9,v3,False)):
            cell=ws.cell(row_i,col,value); cell.font=LABEL_FONT if is_label else (Font(bold=True,size=10) if col==9 else VALUE_FONT)
            cell.alignment=WRAP
    headers=["점검영역","CODE","점검항목","위험도","판정 결과","조치 상태","현재 설정","조치 권고 / 사유","점수"]
    header_row=6
    for i,hd in enumerate(headers,1): ws.cell(header_row,i,hd)
    _style_header_row(ws,header_row,len(headers))
    for row,r in enumerate(results,start=7):
        sk=_status_key(r.get("status")); action=_action_status(r,sk); prefix=f"[점검파일: {r['target_file']}]\n" if r.get("target_file") else ""
        vals=[r.get("category","-"),r.get("code","-"),r.get("title","-"),r.get("importance","-"),sk,action,(prefix+r.get("evidence_description","")) or None,r.get("recommendation_text"),_score(sk)]
        for c,v in enumerate(vals,1):
            cell=ws.cell(row,c,v); cell.border=BORDER_ALL; cell.alignment=WRAP
        imp_style=IMPORTANCE_STYLE.get(r.get("importance")); st_style=STATUS_STYLE[sk]
        if imp_style: ws.cell(row,4).fill=PatternFill("solid",fgColor=imp_style["fill"]); ws.cell(row,4).font=Font(color=imp_style["font"],bold=True)
        ws.cell(row,5).fill=PatternFill("solid",fgColor=st_style["fill"]); ws.cell(row,5).font=Font(color=st_style["font"],bold=True)
        if action == "미조치": ws.cell(row,6).font=Font(color="991B1B",bold=True)
        elif action == "조치 완료": ws.cell(row,6).font=Font(color="166534",bold=True)
        elif action in ("검토 필요","수동 판정"): ws.cell(row,6).font=Font(color="075985",bold=True)
    _autofit(ws,{"A":14,"B":9,"C":31,"D":9,"E":11,"F":13,"G":36,"H":36,"I":8})
    ws.auto_filter.ref=f"A{header_row}:I{max(header_row+1, ws.max_row)}"
    ws.freeze_panes="A7"
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
        "period": meta.get("period", datetime.now(KST).strftime("%Y-%m-%d")),
        "host_count": len(hosts_data),
        "item_count": len(by_code),
    }

    wb = Workbook()
    wb.remove(wb.active)  # 기본 빈 시트 제거

    _build_cover(wb, meta)
    _build_dashboard(wb, hosts_data, total, by_importance, by_category, by_code)
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
