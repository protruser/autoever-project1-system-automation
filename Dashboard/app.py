import streamlit as st
import pandas as pd
from modules.db import list_audit_databases, get_scans, get_hosts

st.set_page_config(page_title="보안 관제 종합 대시보드", layout="wide")

st.sidebar.title("🏢 프로젝트 / 회차 선택")
databases = list_audit_databases()

if not databases:
    st.error("데이터베이스가 없습니다. DB 초기화 스크립트를 먼저 실행해주세요.")
    st.stop()

selected_db = st.sidebar.selectbox("대상 DB", databases)
scans = get_scans(selected_db)

if not scans:
    st.warning("선택된 프로젝트에 진단 이력이 없습니다.")
    st.stop()

scan_options = {f"{s['scan_id']} ({s['scan_date']})": s for s in scans}
selected_scan_label = st.sidebar.selectbox("진단 회차", list(scan_options.keys()))
current_scan = scan_options[selected_scan_label]

st.session_state["selected_db"] = selected_db
st.session_state["current_scan_id"] = current_scan["scan_id"]

st.title(f"🛡️ {current_scan['project_name']}")
st.caption(f"스캔 ID: {current_scan['scan_id']} | 진단자: {current_scan['auditor']} | 일시: {current_scan['scan_date']}")

c1, c2, c3, c4 = st.columns(4)
c1.metric("점검 호스트", f"{current_scan['total_hosts']} 대")
c2.metric("평균 보안 점수", f"{current_scan['average_security_score']} 점")
c3.metric("종합 등급", current_scan["total_grade"])
c4.metric("데이터베이스", selected_db)

st.divider()
st.subheader("호스트별 진단 현황 요약")

hosts = get_hosts(selected_db, current_scan["scan_id"])
if hosts:
    df = pd.DataFrame(hosts)
    
    # 준수율 동적 계산: pass / (pass + vuln) * 100
    valid_checks = df["pass_count"] + df["vuln_count"]
    df["compliance_rate"] = df.apply(
        lambda r: f"{(r['pass_count'] / (r['pass_count'] + r['vuln_count']) * 100):.1f}%" if (r['pass_count'] + r['vuln_count']) > 0 else "100.0%",
        axis=1
    )
    
    df_display = df[["hostname", "ip", "os", "security_score_100", "grade", "pass_count", "vuln_count", "na_count", "compliance_rate"]]
    df_display.columns = ["호스트명", "IP", "운영체제", "보안 점수", "등급", "양호", "취약", "N/A", "준수율"]
    st.dataframe(df_display, use_container_width=True)
