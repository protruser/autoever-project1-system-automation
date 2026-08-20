import streamlit as st
import pandas as pd
from modules.db import fetch_full_report_data
from modules.csv_builder import generate_csv
from modules.json_builder import generate_json
from modules.docx_builder import generate_docx

st.set_page_config(page_title="보고서 내보내기", layout="wide")

selected_db = st.session_state.get("selected_db")
current_scan_id = st.session_state.get("current_scan_id")
if not selected_db or not current_scan_id:
    st.warning("메인 페이지에서 프로젝트와 진단 회차를 먼저 선택해주세요.")
    st.stop()

st.title("📥 진단 보고서 내보내기")
st.caption(f"스캔 ID: `{current_scan_id}`  |  DB: `{selected_db}`")

full_data = fetch_full_report_data(selected_db, current_scan_id)

# ---------- 내보내기 전 요약 통계 ----------
# fetch_full_report_data 반환 구조: {"scan": {...}, "hosts": [{..., "results": [...]}, ...]}
hosts_list = full_data.get("hosts", [])
all_results = []
for h in hosts_list:
    for r in h.get("results", []):
        r = dict(r)
        r["hostname"] = h.get("hostname")
        all_results.append(r)

if all_results:
    df = pd.DataFrame(all_results)
    total = len(df)
    vuln_cnt = (df["status"] == "취약").sum() if "status" in df else 0
    good_cnt = (df["status"] == "양호").sum() if "status" in df else 0
    host_cnt = len(hosts_list)

    st.subheader("📊 내보내기 대상 요약")
    s1, s2, s3, s4 = st.columns(4)
    s1.metric("점검 대상 호스트", f"{host_cnt}대")
    s2.metric("전체 점검 항목", f"{total}건")
    s3.metric("🔴 취약", f"{vuln_cnt}건")
    s4.metric("🟢 양호", f"{good_cnt}건")

st.divider()
st.subheader("📦 내보내기 형식 선택")

c1, c2, c3 = st.columns(3)

with c1:
    with st.container(border=True):
        st.markdown("### 📄 Word 보고서")
        st.caption("경영진/고객 보고용 요약 문서. 표지·요약·상세 항목이 포함됩니다.")
        st.download_button(
            label="DOCX 다운로드",
            data=generate_docx(full_data),
            file_name=f"{current_scan_id}_audit_report.docx",
            mime="application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            use_container_width=True,
        )

with c2:
    with st.container(border=True):
        st.markdown("### 📊 CSV 원시 데이터")
        st.caption("엑셀 등에서 직접 필터링·가공하기 위한 표 형태 데이터입니다.")
        st.download_button(
            label="CSV 다운로드",
            data=generate_csv(full_data["hosts"]),
            file_name=f"{current_scan_id}_results.csv",
            mime="text/csv",
            use_container_width=True,
        )

with c3:
    with st.container(border=True):
        st.markdown("### 📋 JSON 데이터")
        st.caption("다른 시스템 연동·자동화 파이프라인용 원본 데이터입니다.")
        st.download_button(
            label="JSON 다운로드",
            data=generate_json(full_data),
            file_name=f"{current_scan_id}_report.json",
            mime="application/json",
            use_container_width=True,
        )
