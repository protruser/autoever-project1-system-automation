import streamlit as st
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

st.title("📥 진단 보고서 내보내기 (Export)")
st.caption(f"스캔 ID: {current_scan_id} (DB: {selected_db})")

full_data = fetch_full_report_data(selected_db, current_scan_id)
c1, c2, c3 = st.columns(3)

with c1:
    st.subheader("📄 Word 보고서")
    st.download_button(
        label="DOCX 다운로드",
        data=generate_docx(full_data),
        file_name=f"{current_scan_id}_audit_report.docx",
        mime="application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    )

with c2:
    st.subheader("📊 CSV 원시 데이터")
    st.download_button(
        label="CSV 다운로드",
        data=generate_csv(full_data["hosts"]),
        file_name=f"{current_scan_id}_results.csv",
        mime="text/csv"
    )

with c3:
    st.subheader("📋 JSON 데이터")
    st.download_button(
        label="JSON 다운로드",
        data=generate_json(full_data),
        file_name=f"{current_scan_id}_report.json",
        mime="application/json"
    )
