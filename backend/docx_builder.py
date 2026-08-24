import io
from docx import Document
from docx.shared import Inches, Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_TAB_ALIGNMENT, WD_TAB_LEADER
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.oxml import OxmlElement, parse_xml
from docx.oxml.ns import nsdecls, qn

# --- 스타일 및 페이지 분할 방지 유틸리티 ---

def set_cell_background(cell, fill_hex):
    """셀 배경색 지정"""
    tcPr = cell._element.get_or_add_tcPr()
    shd = parse_xml(f'<w:shd {nsdecls("w")} w:fill="{fill_hex}"/>')
    tcPr.append(shd)

def set_cell_margins(cell, top=120, bottom=120, left=150, right=150):
    """셀 내부 패딩 여백 설정"""
    tcPr = cell._element.get_or_add_tcPr()
    tcMar = OxmlElement('w:tcMar')
    for m, val in [('top', top), ('bottom', bottom), ('left', left), ('right', right)]:
        node = OxmlElement(f'w:{m}')
        node.set(qn('w:w'), str(val))
        node.set(qn('w:type'), 'dxa')
        tcMar.append(node)
    tcPr.append(tcMar)

def set_table_borders(table, color="CBD5E1", sz="4", val="single"):
    """테이블 전체 테두리 설정"""
    tblPr = table._element.xpath('w:tblPr')
    if tblPr:
        borders = parse_xml(
            f'<w:tblBorders {nsdecls("w")}>'
            f'  <w:top w:val="{val}" w:sz="{sz}" w:space="0" w:color="{color}"/>'
            f'  <w:bottom w:val="{val}" w:sz="{sz}" w:space="0" w:color="{color}"/>'
            f'  <w:insideH w:val="{val}" w:sz="{sz}" w:space="0" w:color="{color}"/>'
            f'  <w:insideV w:val="{val}" w:sz="{sz}" w:space="0" w:color="{color}"/>'
            f'  <w:left w:val="none"/>'
            f'  <w:right w:val="none"/>'
            f'</w:tblBorders>'
        )
        tblPr[0].append(borders)

def prevent_table_page_split(table):
    """
    [핵심] 표가 페이지 경계에서 두 동강 나는 현상 완벽 방지
    1. 행 쪼개짐 방지 (cantSplit)
    2. 이전 행과 다음 행이 떨어지지 않게 결합 (keep_with_next)
    """
    for row_idx, row in enumerate(table.rows):
        # 1. 행 쪼개짐 방지 XML 추가
        trPr = row._tr.get_or_add_trPr()
        trPr.append(parse_xml(f'<w:cantSplit {nsdecls("w")}/>'))
        
        # 2. 마지막 행을 제외한 모든 행에 keep_with_next 설정 -> 표 전체가 함께 묶여 이동
        if row_idx < len(table.rows) - 1:
            for cell in row.cells:
                for p in cell.paragraphs:
                    p.paragraph_format.keep_with_next = True

def format_run(run, font_name="Malgun Gothic", size=10, bold=False, color_rgb=(51, 51, 51)):
    """폰트 서식 통일 적용"""
    run.font.name = font_name
    run._element.rPr.rFonts.set(qn('w:eastAsia'), font_name)
    run.font.size = Pt(size)
    run.bold = bold
    run.font.color.rgb = RGBColor(*color_rgb)

def add_styled_paragraph(doc, text="", font_size=10, bold=False, color=(51, 51, 51), align=WD_ALIGN_PARAGRAPH.LEFT, space_after=4):
    p = doc.add_paragraph()
    p.alignment = align
    p.paragraph_format.space_after = Pt(space_after)
    p.paragraph_format.line_spacing = 1.15
    if text:
        r = p.add_run(text)
        format_run(r, size=font_size, bold=bold, color_rgb=color)
    return p

def add_toc_line(doc, title, level=1):
    """점선 리더가 포함된 목차 라인 추가"""
    p = doc.add_paragraph()
    p.paragraph_format.space_after = Pt(4)
    p.paragraph_format.tab_stops.add_tab_stop(Inches(6.3), WD_TAB_ALIGNMENT.RIGHT, WD_TAB_LEADER.DOTS)
    
    prefix = "" if level == 1 else "    "
    font_sz = 10.5 if level == 1 else 9.5
    bold = True if level == 1 else False
    color = (30, 41, 59) if level == 1 else (71, 85, 105)
    
    r = p.add_run(f"{prefix}{title}")
    format_run(r, size=font_sz, bold=bold, color_rgb=color)


# --- 메인 보고서 빌더 ---

def generate_docx(full_data):
    doc = Document()

    # 페이지 여백 설정 (1인치)
    for section in doc.sections:
        section.top_margin = Inches(1)
        section.bottom_margin = Inches(1)
        section.left_margin = Inches(1)
        section.right_margin = Inches(1)

    scan = full_data.get("scan", {})
    hosts = full_data.get("hosts", [])

    # ==========================================
    # 1. 표지 (Cover Page)
    # ==========================================
    p_top = doc.add_paragraph()
    p_top.paragraph_format.space_before = Pt(80)

    add_styled_paragraph(doc, "SegFault Security Assessment", font_size=13, bold=True, color=(255, 87, 34), align=WD_ALIGN_PARAGRAPH.CENTER, space_after=18)
    
    project_name = scan.get("project_name", "KISA 보안 취약점 진단 보고서")
    add_styled_paragraph(doc, project_name, font_size=23, bold=True, color=(30, 41, 59), align=WD_ALIGN_PARAGRAPH.CENTER, space_after=10)
    add_styled_paragraph(doc, "보안 취약점 점검 결과 및 조치 권고서", font_size=13, color=(100, 116, 139), align=WD_ALIGN_PARAGRAPH.CENTER, space_after=160)

    # 표지 메타정보 표
    meta_table = doc.add_table(rows=4, cols=2)
    meta_table.alignment = WD_TABLE_ALIGNMENT.CENTER
    meta_data = [
        ("스캔 ID", str(scan.get("scan_id", "-"))),
        ("진단 일시", str(scan.get("scan_date", "-"))),
        ("종합 점수 / 등급", f"{scan.get('average_security_score', '-')}점 ({scan.get('total_grade', '-')})"),
        ("점검 대상", f"총 {len(hosts)}대 서버 / 자산")
    ]
    for idx, (label, val) in enumerate(meta_data):
        c1, c2 = meta_table.rows[idx].cells
        c1.text, c2.text = label, val
        format_run(c1.paragraphs[0].runs[0], size=9.5, bold=True, color_rgb=(71, 85, 105))
        format_run(c2.paragraphs[0].runs[0], size=9.5, bold=False, color_rgb=(30, 41, 59))
        set_cell_background(c1, "F8FAFC")
        set_cell_margins(c1, top=100, bottom=100, left=120, right=120)
        set_cell_margins(c2, top=100, bottom=100, left=120, right=120)
    
    set_table_borders(meta_table, color="CBD5E1")
    prevent_table_page_split(meta_table)
    doc.add_page_break()

    # ==========================================
    # 2. 깔끔해진 목차 (Table of Contents)
    # ==========================================
    add_styled_paragraph(doc, "목   차", font_size=18, bold=True, color=(15, 23, 42), align=WD_ALIGN_PARAGRAPH.CENTER, space_after=24)
    
    add_toc_line(doc, "1. 취약점 점검 및 조치 수행 정보", level=1)
    add_toc_line(doc, "1.1. 개요", level=2)
    add_toc_line(doc, "1.2. 점검 대상 및 결과 요약", level=2)
    
    add_toc_line(doc, "2. 취약점 상세 내용 및 보안 권고안", level=1)
    # [개선] 60~70개 항목을 다 풀지 않고 서버(호스트) 단위까지만 표기하여 1페이지로 축소
    for h_idx, h in enumerate(hosts, start=1):
        h_name = h.get('hostname', 'Host')
        h_ip = h.get('ip', '-')
        vuln_cnt = sum(1 for r in h.get('results', []) if "취약" in r.get('status', ''))
        add_toc_line(doc, f"2.{h_idx}. {h_name} ({h_ip}) - 취약 {vuln_cnt}건", level=2)

    doc.add_page_break()

    # ==========================================
    # 3. 진단 수행 정보 & 결과 요약 (1장)
    # ==========================================
    add_styled_paragraph(doc, "1. 취약점 점검 및 조치 수행 정보", font_size=15, bold=True, color=(15, 23, 42), space_after=8)
    
    add_styled_paragraph(doc, "1.1. 개요", font_size=12, bold=True, color=(30, 41, 59), space_after=4)
    add_styled_paragraph(doc, f"본 보고서는 [{project_name}] 대상 시스템에 대한 취약점 진단 및 조치를 수행한 결과입니다. 발견된 취약점에 대한 실질적인 대응 방안을 제시하여 침해사고를 예방하고 정보보호 수준을 향상하는 데 목적이 있습니다.", font_size=9.5, color=(71, 85, 105), space_after=12)

    add_styled_paragraph(doc, "1.2. 점검 대상 및 결과 요약", font_size=12, bold=True, color=(30, 41, 59), space_after=6)
    
    target_table = doc.add_table(rows=1, cols=5)
    target_table.alignment = WD_TABLE_ALIGNMENT.CENTER
    set_table_borders(target_table, color="CBD5E1")
    
    hdrs = ["No.", "호스트명", "IP 주소", "OS", "보안점수 / 준수율"]
    widths = [Inches(0.6), Inches(1.8), Inches(1.5), Inches(1.3), Inches(1.3)]
    for i, h in enumerate(target_table.rows[0].cells):
        h.text = hdrs[i]
        set_cell_background(h, "1E293B")
        set_cell_margins(h, 110, 110, 100, 100)
        format_run(h.paragraphs[0].runs[0], size=9, bold=True, color_rgb=(255, 255, 255))
        h.paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.CENTER
        h.width = widths[i]

    for idx, h in enumerate(hosts, start=1):
        row_cells = target_table.add_row().cells
        row_data = [
            str(idx),
            h.get("hostname", "-"),
            h.get("ip", "-"),
            h.get("os", "-"),
            f"{h.get('security_score_100', '-')}점 ({h.get('compliance_rate', '-')})"
        ]
        for i, val in enumerate(row_data):
            row_cells[i].text = val
            set_cell_margins(row_cells[i], 90, 90, 90, 90)
            format_run(row_cells[i].paragraphs[0].runs[0], size=9, color_rgb=(51, 65, 85))
            if i in [0, 4]:
                row_cells[i].paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.CENTER
            row_cells[i].width = widths[i]

    prevent_table_page_split(target_table)
    doc.add_paragraph().paragraph_format.space_after = Pt(16)

    # ==========================================
    # 4. 취약점 상세 내용 및 보안 권고안 (2장)
    # ==========================================
    add_styled_paragraph(doc, "2. 취약점 상세 내용 및 보안 권고안", font_size=15, bold=True, color=(15, 23, 42), space_after=12)

    for h_idx, h in enumerate(hosts, start=1):
        h_title = f"2.{h_idx}. {h.get('hostname', 'Host')} ({h.get('ip', '-')})"
        p_host = add_styled_paragraph(doc, h_title, font_size=12.5, bold=True, color=(30, 41, 59), space_after=4)
        p_host.paragraph_format.keep_with_next = True  # 호스트 제목이 페이지 맨 밑에 홀로 남지 않도록 방지
        
        meta_str = f"OS: {h.get('os', '-')}  |  보안 점수: {h.get('security_score_100', '-')}점  |  준수율: {h.get('compliance_rate', '-')}"
        p_meta = add_styled_paragraph(doc, meta_str, font_size=9, color=(100, 116, 139), space_after=10)
        p_meta.paragraph_format.keep_with_next = True

        results = h.get("results", [])
        if not results:
            add_styled_paragraph(doc, "진단 결과 항목이 존재하지 않습니다.", font_size=9, color=(148, 163, 184), space_after=12)
            continue

        for r_idx, r in enumerate(results, start=1):
            code = r.get("code", "")
            title = r.get("title", "")
            status = r.get("status", "")
            importance = str(r.get("importance", "")).upper()
            category = r.get("category", "")
            target_file = r.get("target_file", "")
            evidence = r.get("evidence_description", "") or r.get("evidence", "")
            guide = r.get("guide", "")

            # 개별 취약점 상세 테이블 생성
            vuln_tbl = doc.add_table(rows=5, cols=4)
            vuln_tbl.alignment = WD_TABLE_ALIGNMENT.CENTER
            set_table_borders(vuln_tbl, color="CBD5E1")
            c_w = [Inches(1.2), Inches(2.2), Inches(1.2), Inches(2.2)]

            # 1행: 헤더 (항목명 및 코드)
            hdr_cell = vuln_tbl.cell(0, 0)
            hdr_cell.merge(vuln_tbl.cell(0, 3))
            hdr_cell.text = f"[{code}] {title}"
            set_cell_background(hdr_cell, "F1F5F9")
            set_cell_margins(hdr_cell, 110, 110, 110, 110)
            format_run(hdr_cell.paragraphs[0].runs[0], size=10, bold=True, color_rgb=(15, 23, 42))

            # 2행: 점검영역 / 위험도
            vuln_tbl.cell(1, 0).text = "점검영역"
            vuln_tbl.cell(1, 1).text = category or "-"
            vuln_tbl.cell(1, 2).text = "위험도"
            vuln_tbl.cell(1, 3).text = importance or "-"

            # 3행: 진단결과 / 점검 대상 파일
            vuln_tbl.cell(2, 0).text = "진단 결과"
            vuln_tbl.cell(2, 1).text = status or "-"
            vuln_tbl.cell(2, 2).text = "점검 파일"
            vuln_tbl.cell(2, 3).text = target_file or "-"

            # 2, 3행 셀 서식
            for row_i in [1, 2]:
                for col_i in range(4):
                    c = vuln_tbl.cell(row_i, col_i)
                    set_cell_margins(c, 80, 80, 90, 90)
                    if col_i in [0, 2]:
                        set_cell_background(c, "F8FAFC")
                        if c.paragraphs[0].runs:
                            format_run(c.paragraphs[0].runs[0], size=9, bold=True, color_rgb=(71, 85, 105))
                    else:
                        if c.paragraphs[0].runs:
                            is_vuln = (col_i == 1 and row_i == 2 and "취약" in status)
                            color_val = (220, 38, 38) if is_vuln else (30, 41, 59)
                            format_run(c.paragraphs[0].runs[0], size=9, bold=is_vuln, color_rgb=color_val)

            # 4행: 점검 증적(현재 설정)
            lbl_ev = vuln_tbl.cell(3, 0)
            lbl_ev.text = "점검 증적\n(현재 설정)"
            set_cell_background(lbl_ev, "F8FAFC")
            set_cell_margins(lbl_ev, 90, 90, 90, 90)
            format_run(lbl_ev.paragraphs[0].runs[0], size=9, bold=True, color_rgb=(71, 85, 105))

            cnt_ev = vuln_tbl.cell(3, 1)
            cnt_ev.merge(vuln_tbl.cell(3, 3))
            cnt_ev.text = evidence if evidence else "특이사항 없음"
            set_cell_background(cnt_ev, "FAFAFA")
            set_cell_margins(cnt_ev, 90, 90, 110, 110)
            format_run(cnt_ev.paragraphs[0].runs[0], size=9, color_rgb=(51, 65, 85))

            # 5행: 보안 권고안(조치 방안)
            lbl_gd = vuln_tbl.cell(4, 0)
            lbl_gd.text = "보안 권고안\n(조치 방안)"
            set_cell_background(lbl_gd, "F8FAFC")
            set_cell_margins(lbl_gd, 90, 90, 90, 90)
            format_run(lbl_gd.paragraphs[0].runs[0], size=9, bold=True, color_rgb=(71, 85, 105))

            cnt_gd = vuln_tbl.cell(4, 1)
            cnt_gd.merge(vuln_tbl.cell(4, 3))
            cnt_gd.text = guide if guide else "표준 보안 가이드라인에 따라 설정 유지 권장"
            set_cell_background(cnt_gd, "FFFFFF")
            set_cell_margins(cnt_gd, 90, 90, 110, 110)
            format_run(cnt_gd.paragraphs[0].runs[0], size=9, color_rgb=(15, 23, 42))

            for row in vuln_tbl.rows:
                for idx_c, cell in enumerate(row.cells):
                    if idx_c < len(c_w):
                        cell.width = c_w[idx_c]

            # [핵심] 표 쪼개짐 방지 적용
            prevent_table_page_split(vuln_tbl)

            doc.add_paragraph().paragraph_format.space_after = Pt(8)

    output = io.BytesIO()
    doc.save(output)
    return output.getvalue()
