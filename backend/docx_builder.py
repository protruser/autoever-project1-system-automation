"""운영자용 요약 보안 진단 보고서(DOCX) 생성기.

원본 전체 결과는 XLSX/JSON으로 제공하고, DOCX는 의사결정에 필요한 취약·검토
항목만 상세히 보여 준다. 따라서 대상/항목 수가 증가해도 불필요하게 수백 페이지로
늘어나지 않는다.
"""
import io
import re
from collections import Counter, defaultdict

from docx import Document
from docx.enum.section import WD_SECTION
from docx.enum.table import WD_TABLE_ALIGNMENT, WD_CELL_VERTICAL_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement, parse_xml
from docx.oxml.ns import nsdecls, qn
from docx.shared import Inches, Pt, RGBColor

NAVY = "0F172A"; BLUE = "2563EB"; SLATE = "475569"; LIGHT = "F8FAFC"; BORDER = "CBD5E1"
STATUS = {
    "양호": ("DCFCE7", (22, 101, 52)),
    "취약": ("FEE2E2", (153, 27, 27)),
    "검토": ("E0F2FE", (7, 89, 133)),
    "N/A": ("F1F5F9", (71, 85, 105)),
}
RISK = {"상": ("FEE2E2", (153, 27, 27)), "중": ("FEF3C7", (146, 64, 14)), "하": ("E0F2FE", (7, 89, 133))}


def status_key(value):
    s = str(value or "").strip().upper()
    if s in {"양호", "OK", "GOOD", "PASS"}: return "양호"
    if s in {"취약", "FAIL", "VULNERABLE"}: return "취약"
    if s in {"N/A", "NA", "NOT APPLICABLE", "해당없음"}: return "N/A"
    return "검토"  # 수동확인, 예외, 판정불가 포함


def clean(value, default="-"):
    """DB 텍스트/HTML의 공백을 정리해 표에 그대로 노출되는 깨짐을 줄인다."""
    s = str(value or "").replace("<br>", "\n").replace("<br/>", "\n").replace("<br />", "\n")
    s = re.sub(r"[ \t]+", " ", s)
    s = re.sub(r" *\n *", "\n", s).strip()
    return s or default


def shade(cell, fill):
    tcPr = cell._tc.get_or_add_tcPr()
    tcPr.append(parse_xml(f'<w:shd {nsdecls("w")} w:fill="{fill}"/>'))


def margins(cell, top=80, bottom=80, left=100, right=100):
    tcPr = cell._tc.get_or_add_tcPr(); tcMar = OxmlElement("w:tcMar")
    for name, val in (("top", top), ("bottom", bottom), ("left", left), ("right", right)):
        el = OxmlElement(f"w:{name}"); el.set(qn("w:w"), str(val)); el.set(qn("w:type"), "dxa"); tcMar.append(el)
    tcPr.append(tcMar)


def set_borders(table):
    tblPr = table._tbl.tblPr
    tblPr.append(parse_xml(
        f'<w:tblBorders {nsdecls("w")}><w:top w:val="single" w:sz="4" w:color="{BORDER}"/>'
        f'<w:left w:val="single" w:sz="4" w:color="{BORDER}"/><w:bottom w:val="single" w:sz="4" w:color="{BORDER}"/>'
        f'<w:right w:val="single" w:sz="4" w:color="{BORDER}"/><w:insideH w:val="single" w:sz="4" w:color="{BORDER}"/>'
        f'<w:insideV w:val="single" w:sz="4" w:color="{BORDER}"/></w:tblBorders>'))


def font(run, size=9, bold=False, color=(30, 41, 59)):
    run.font.name = "Malgun Gothic"; run._element.rPr.rFonts.set(qn("w:eastAsia"), "Malgun Gothic")
    run.font.size = Pt(size); run.bold = bold; run.font.color.rgb = RGBColor(*color)


def write_cell(cell, value, size=9, bold=False, color=(30, 41, 59), align=None):
    cell.text = clean(value, "")
    margins(cell); cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
    p = cell.paragraphs[0]
    if align is not None: p.alignment = align
    p.paragraph_format.space_after = Pt(0); p.paragraph_format.line_spacing = 1.15
    for run in p.runs: font(run, size, bold, color)


def no_split(table):
    for row in table.rows:
        trPr = row._tr.get_or_add_trPr(); trPr.append(parse_xml(f'<w:cantSplit {nsdecls("w")}/>'))


def paragraph(doc, text="", size=9.5, bold=False, color=(51, 65, 85), align=WD_ALIGN_PARAGRAPH.LEFT, after=6, before=0, style=None):
    p = doc.add_paragraph(style=style) if style else doc.add_paragraph()
    p.alignment = align; p.paragraph_format.space_after = Pt(after); p.paragraph_format.space_before = Pt(before); p.paragraph_format.line_spacing = 1.2
    r = p.add_run(clean(text, "")); font(r, size, bold, color)
    return p


def heading(doc, text, level=1):
    p = doc.add_paragraph(style=f"Heading {level}")
    p.paragraph_format.space_before = Pt(18 if level == 1 else 12); p.paragraph_format.space_after = Pt(7)
    p.paragraph_format.keep_with_next = True
    r = p.add_run(text); font(r, 16 if level == 1 else 12, True, (15, 23, 42))
    return p


def add_page_footer(doc):
    section = doc.sections[0]; footer = section.footer; p = footer.paragraphs[0]
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = p.add_run("HIGHFIVE SECURITY  |  "); font(r, 8, False, (100, 116, 139))
    for typ, text in (("begin", None), ("instr", "PAGE"), ("end", None)):
        el = OxmlElement("w:fldChar" if typ != "instr" else "w:instrText")
        if typ != "instr": el.set(qn("w:fldCharType"), typ)
        else: el.set(qn("xml:space"), "preserve"); el.text = text
        r._r.append(el)


def add_toc(doc):
    p = doc.add_paragraph(); p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = p.add_run("목  차"); font(r, 18, True, (15, 23, 42))
    p = doc.add_paragraph(); p.paragraph_format.space_before = Pt(15)
    fld = OxmlElement("w:fldSimple"); fld.set(qn("w:instr"), 'TOC \\o "1-2" \\h \\z \\u')
    p._p.append(fld)
    paragraph(doc, "문서를 연 뒤 목차에서 마우스 오른쪽 버튼 → ‘필드 업데이트’를 선택하면 페이지 번호가 반영됩니다.", 8.5, False, (100,116,139), after=0)


def data_summary(hosts):
    totals = Counter(); risk = Counter(); categories = defaultdict(Counter); repeated = defaultdict(list); priority = []
    for h in hosts:
        for r in h.get("results", []):
            st = status_key(r.get("status")); imp = clean(r.get("importance"), "중")
            totals[st] += 1; categories[clean(r.get("category"), "기타")][st] += 1
            if st == "취약":
                risk[imp] += 1; repeated[(clean(r.get("code")), clean(r.get("title")))].append(h.get("hostname", "-"))
                priority.append((0 if imp == "상" else 1 if imp == "중" else 2, h, r))
    priority.sort(key=lambda x: x[0])
    return totals, risk, categories, repeated, priority


def summary_table(doc, totals, risk):
    table = doc.add_table(rows=2, cols=7); table.alignment = WD_TABLE_ALIGNMENT.CENTER; set_borders(table)
    labels = [("양호", totals["양호"]), ("취약", totals["취약"]), ("검토", totals["검토"]), ("N/A", totals["N/A"]), ("상 위험", risk["상"]), ("중 위험", risk["중"]), ("하 위험", risk["하"])]
    for i, (label, count) in enumerate(labels):
        fill, col = STATUS.get(label, RISK.get(label[0], (LIGHT, (71,85,105))))
        write_cell(table.cell(0,i), label, 8.5, True, col, WD_ALIGN_PARAGRAPH.CENTER); shade(table.cell(0,i), fill)
        write_cell(table.cell(1,i), f"{count}건", 16, True, col, WD_ALIGN_PARAGRAPH.CENTER); shade(table.cell(1,i), fill)
    no_split(table)


def simple_table(doc, headers, rows, widths=None):
    table = doc.add_table(rows=1, cols=len(headers)); table.alignment = WD_TABLE_ALIGNMENT.CENTER; set_borders(table)
    for i, h in enumerate(headers):
        write_cell(table.cell(0,i), h, 8.5, True, (255,255,255), WD_ALIGN_PARAGRAPH.CENTER); shade(table.cell(0,i), NAVY)
        if widths: table.cell(0,i).width = Inches(widths[i])
    for row in rows:
        cells = table.add_row().cells
        for i, val in enumerate(row):
            write_cell(cells[i], val, 8.5, False, (51,65,85), WD_ALIGN_PARAGRAPH.CENTER if i in (0, len(row)-1) else None)
            if widths: cells[i].width = Inches(widths[i])
    no_split(table); return table


def detailed_item(doc, host, r):
    st = status_key(r.get("status")); imp = clean(r.get("importance"), "중"); sfill, scol = STATUS[st]
    table = doc.add_table(rows=5, cols=4); table.alignment = WD_TABLE_ALIGNMENT.CENTER; set_borders(table)
    title = table.cell(0,0).merge(table.cell(0,3)); write_cell(title, f"[{clean(r.get('code'))}] {clean(r.get('title'))}", 10, True); shade(title, "F1F5F9")
    fields = [("위험도", imp, "진단 결과", st), ("점검영역", clean(r.get("category")), "점검 파일", clean(r.get("target_file"))), ("점검 증적", clean(r.get("evidence_description") or r.get("evidence"), "특이사항 없음"), None, None)]
    for ridx, values in enumerate(fields, 1):
        if values[3] is None:
            label = table.cell(ridx,0); value = table.cell(ridx,1).merge(table.cell(ridx,3))
            write_cell(label, values[0], 8.5, True, (71,85,105)); shade(label, LIGHT)
            write_cell(value, values[1], 8.5); shade(value, "FAFAFA")
        else:
            for c, v in enumerate(values):
                write_cell(table.cell(ridx,c), v, 8.5, c in (0,2), (71,85,105) if c in (0,2) else (30,41,59), WD_ALIGN_PARAGRAPH.CENTER if c in (1,3) else None)
                if c in (0,2): shade(table.cell(ridx,c), LIGHT)
            shade(table.cell(ridx,3), sfill)
            for run in table.cell(ridx,3).paragraphs[0].runs: font(run, 8.5, True, scol)
    # last row: recommendation (reuse newly created sixth row is more legible)
    row = table.add_row().cells; label=row[0]; value=row[1].merge(row[3])
    write_cell(label, "조치 권고", 8.5, True, (71,85,105)); shade(label, LIGHT)
    write_cell(value, clean(r.get("recommendation_text") or r.get("guide"), "관리자 검토 후 기관 보안 정책에 따라 조치하세요."), 8.5)
    no_split(table)


def generate_docx(full_data):
    doc = Document(); section = doc.sections[0]
    section.top_margin = Inches(.75); section.bottom_margin = Inches(.7); section.left_margin = Inches(.72); section.right_margin = Inches(.72)
    styles = doc.styles; styles["Normal"].font.name = "Malgun Gothic"; styles["Normal"]._element.rPr.rFonts.set(qn("w:eastAsia"), "Malgun Gothic")
    add_page_footer(doc)
    scan = full_data.get("scan") or {}; hosts = full_data.get("hosts") or []
    totals, risk, categories, repeated, priority = data_summary(hosts)
    project = clean(scan.get("project_name"), "주요정보통신기반시설 시스템 취약점 진단")

    # Cover
    paragraph(doc, "HIGHFIVE SECURITY", 13, True, (37,99,235), WD_ALIGN_PARAGRAPH.CENTER, after=18, before=105)
    paragraph(doc, "보안 취약점 진단\n결과 보고서", 27, True, (15,23,42), WD_ALIGN_PARAGRAPH.CENTER, after=14)
    paragraph(doc, project, 12, False, (100,116,139), WD_ALIGN_PARAGRAPH.CENTER, after=70)
    cover = simple_table(doc, ["구분", "내용"], [["스캔 ID", clean(scan.get("scan_id"))], ["진단 일시", clean(scan.get("scan_date"))], ["종합 점수 / 등급", f"{clean(scan.get('average_security_score'))}점 / {clean(scan.get('total_grade'))}"], ["점검 대상", f"총 {len(hosts)}대 서버"]], [1.5, 4.8])
    paragraph(doc, f"핵심 결과  |  취약 {totals['취약']}건 · 검토 {totals['검토']}건 · 상 위험 {risk['상']}건", 11, True, (153,27,27), WD_ALIGN_PARAGRAPH.CENTER, before=28)
    doc.add_page_break()

    add_toc(doc); doc.add_page_break()
    heading(doc, "1. 진단 개요", 1)
    paragraph(doc, f"본 보고서는 {project} 대상 시스템에 대한 기술적 취약점 진단 결과를 요약한 문서입니다. 상세 원본 결과는 별도 XLSX 내보내기 파일에서 필터·검색할 수 있습니다.")
    heading(doc, "2. 종합 진단 현황", 1); summary_table(doc, totals, risk)
    heading(doc, "2.1. 호스트별 현황", 2)
    host_rows=[]
    for i,h in enumerate(hosts,1):
        rs=h.get("results",[]); vuln=sum(status_key(r.get("status"))=="취약" for r in rs); review=sum(status_key(r.get("status"))=="검토" for r in rs)
        host_rows.append([i, clean(h.get("hostname")), clean(h.get("ip")), clean(h.get("os")), f"{clean(h.get('security_score_100'))}점", f"취약 {vuln} / 검토 {review}"])
    simple_table(doc, ["No.","호스트명","IP 주소","OS","보안 점수","조치 대상"], host_rows, [.45,1.05,1.15,1.25,.8,1.25])
    heading(doc, "2.2. 점검 영역별 취약 현황", 2)
    category_rows=[]
    for cat,cnt in sorted(categories.items(), key=lambda x:x[1]["취약"], reverse=True):
        category_rows.append([cat, cnt["취약"], cnt["검토"], cnt["양호"], cnt["N/A"]])
    simple_table(doc,["점검 영역","취약","검토","양호","N/A"],category_rows,[2.8,.8,.8,.8,.8])
    doc.add_page_break()

    heading(doc, "3. 우선 조치 권고", 1)
    paragraph(doc, "위험도 ‘상’ 취약점과 여러 서버에서 반복적으로 발견된 취약점을 우선 조치 대상으로 제시합니다.", after=8)
    top_rows=[]
    for _,h,r in priority[:15]: top_rows.append([clean(r.get("importance"),"중"), clean(r.get("code")), clean(r.get("title")), f"{clean(h.get('hostname'))} ({clean(h.get('ip'))})"])
    if top_rows: simple_table(doc,["위험도","코드","취약점","대상 서버"],top_rows,[.75,.75,2.8,2.0])
    else: paragraph(doc,"현재 ‘취약’으로 판정된 항목이 없습니다.",9,False,(100,116,139))
    heading(doc, "3.1. 반복 취약점", 2)
    repeated_rows=[]
    for (code,title), names in sorted(repeated.items(), key=lambda x:len(x[1]), reverse=True):
        if len(names) >= 2: repeated_rows.append([code,title,", ".join(names),f"{len(names)}대"])
    if repeated_rows: simple_table(doc,["코드","취약점","발견 서버","영향 범위"],repeated_rows,[.75,2.5,2.2,.75])
    else: paragraph(doc,"2대 이상에서 반복된 취약점이 없습니다.",9,False,(100,116,139))
    doc.add_page_break()

    heading(doc, "4. 서버별 조치 대상 상세", 1)
    paragraph(doc, "이 장에는 조치가 필요한 ‘취약’ 및 관리자의 판단이 필요한 ‘검토’ 항목만 수록합니다. 양호 및 N/A 항목은 XLSX 전체 결과를 참조하세요.", 9, False, (100,116,139), after=12)
    for n,h in enumerate(hosts,1):
        actionable=[r for r in h.get("results",[]) if status_key(r.get("status")) in {"취약","검토"}]
        if not actionable: continue
        heading(doc, f"4.{n}. {clean(h.get('hostname'))} ({clean(h.get('ip'))})", 2)
        paragraph(doc, f"OS: {clean(h.get('os'))}  |  보안 점수: {clean(h.get('security_score_100'))}점  |  조치 대상: {len(actionable)}건", 8.8, False, (100,116,139), after=8)
        for r in sorted(actionable, key=lambda x:(0 if clean(x.get('importance'))=='상' else 1 if clean(x.get('importance'))=='중' else 2, clean(x.get('code')))):
            detailed_item(doc,h,r); paragraph(doc,"",after=6)
    output=io.BytesIO(); doc.save(output); return output.getvalue()
