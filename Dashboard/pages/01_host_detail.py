import streamlit as st
import pandas as pd
from modules.db import get_hosts, get_results

st.set_page_config(page_title="호스트 세부 진단 결과", layout="wide")

selected_db = st.session_state.get("selected_db")
current_scan_id = st.session_state.get("current_scan_id")

if not selected_db or not current_scan_id:
    st.warning("메인 페이지에서 프로젝트와 진단 회차를 먼저 선택해주세요.")
    st.stop()

hosts = get_hosts(selected_db, current_scan_id)
host_map = {f"{h['hostname']} ({h['ip']})": h for h in hosts}
selected_host_label = st.selectbox("호스트 선택", list(host_map.keys()))
selected_host = host_map[selected_host_label]

results = get_results(selected_db, selected_host["id"])
vuln_items = [r for r in results if r["status"] == "취약"]

st.subheader(f"⚠️ 취약 항목 목록 ({len(vuln_items)}건)")
for item in vuln_items:
    st.markdown(f"**[{item['code']}] {item['title']}** (중요도: {item['importance']})")
    st.caption(f"대상 경로: `{item['target_file']}` | 조치 가이드: {item['guide']}")
    st.divider()

st.subheader("전체 67개 점검 항목 세부 내역")
st.dataframe(pd.DataFrame(results)[["code", "category", "title", "importance", "status", "target_file", "evidence_description", "guide"]], use_container_width=True)
