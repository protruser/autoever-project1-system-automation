import streamlit as st
import pandas as pd
from modules.db import get_hosts, get_results

st.set_page_config(page_title="호스트 세부 진단 결과", layout="wide")

# ---------- 공통 색상/배지 헬퍼 ----------
IMPORTANCE_COLOR = {"상": "#e74c3c", "중": "#f39c12", "하": "#95a5a6"}
STATUS_COLOR = {"취약": "#e74c3c", "양호": "#2ecc71", "수동확인": "#f39c12"}


def badge(text: str, color: str) -> str:
    return (
        f"<span style='background-color:{color};color:white;"
        f"padding:2px 10px;border-radius:12px;font-size:0.8em;font-weight:600'>"
        f"{text}</span>"
    )


def style_status(val):
    color = STATUS_COLOR.get(val, "#ecf0f1")
    return f"background-color:{color}22;color:{color};font-weight:600"


# ---------- 진입 가드 ----------
selected_db = st.session_state.get("selected_db")
current_scan_id = st.session_state.get("current_scan_id")
if not selected_db or not current_scan_id:
    st.warning("메인 페이지에서 프로젝트와 진단 회차를 먼저 선택해주세요.")
    st.stop()

hosts = get_hosts(selected_db, current_scan_id)
if not hosts:
    st.info("호스트 정보가 없습니다.")
    st.stop()

# ---------- 헤더: 호스트 선택 ----------
st.title("🖥️ 호스트 세부 진단 결과")

host_map = {f"{h['hostname']} ({h['ip']})": h for h in hosts}
selected_host_label = st.selectbox("호스트 선택", list(host_map.keys()))
selected_host = host_map[selected_host_label]

results = get_results(selected_db, selected_host["id"])
if not results:
    st.info("이 호스트에 대한 점검 결과가 없습니다.")
    st.stop()

df = pd.DataFrame(results)

# ---------- KPI 카드 ----------
total = len(df)
vuln_cnt = (df["status"] == "취약").sum()
good_cnt = (df["status"] == "양호").sum()
manual_cnt = (df["status"] == "수동확인").sum()
pass_rate = round(good_cnt / total * 100, 1) if total else 0

k1, k2, k3, k4, k5 = st.columns(5)
k1.metric("전체 점검 항목", f"{total}건")
k2.metric("🔴 취약", f"{vuln_cnt}건")
k3.metric("🟢 양호", f"{good_cnt}건")
k4.metric("🟡 수동확인", f"{manual_cnt}건")
k5.metric("양호율", f"{pass_rate}%")

st.progress(pass_rate / 100)
st.divider()

# ---------- 탭 구성 ----------
tab_summary, tab_vuln, tab_all = st.tabs(["📊 요약", "⚠️ 취약 항목", "📋 전체 내역"])

with tab_summary:
    st.subheader("중요도별 취약 항목 분포")
    vuln_df = df[df["status"] == "취약"]
    if vuln_df.empty:
        st.success("취약 항목이 없습니다. 🎉")
    else:
        importance_counts = (
            vuln_df["importance"].value_counts().reindex(["상", "중", "하"]).fillna(0)
        )
        st.bar_chart(importance_counts)

        st.subheader("카테고리별 취약 항목")
        cat_counts = vuln_df["category"].value_counts()
        st.bar_chart(cat_counts)

with tab_vuln:
    # 사이드바 필터
    with st.sidebar:
        st.markdown("### 🔍 필터")
        cat_options = ["전체"] + sorted(df["category"].dropna().unique().tolist())
        selected_cat = st.selectbox("카테고리", cat_options)
        imp_options = ["전체", "상", "중", "하"]
        selected_imp = st.selectbox("중요도", imp_options)

    vuln_df = df[df["status"] == "취약"].copy()
    if selected_cat != "전체":
        vuln_df = vuln_df[vuln_df["category"] == selected_cat]
    if selected_imp != "전체":
        vuln_df = vuln_df[vuln_df["importance"] == selected_imp]

    st.subheader(f"취약 항목 목록 ({len(vuln_df)}건)")

    if vuln_df.empty:
        st.info("조건에 해당하는 취약 항목이 없습니다.")
    else:
        # 중요도 순 정렬 (상 > 중 > 하)
        order = {"상": 0, "중": 1, "하": 2}
        vuln_df["_order"] = vuln_df["importance"].map(order).fillna(3)
        vuln_df = vuln_df.sort_values("_order")

        for _, item in vuln_df.iterrows():
            imp_badge = badge(item["importance"], IMPORTANCE_COLOR.get(item["importance"], "#7f8c8d"))
            header = f"[{item['code']}] {item['title']}"
            with st.expander(header, expanded=(item["importance"] == "상")):
                st.markdown(f"중요도: {imp_badge}", unsafe_allow_html=True)
                st.markdown(f"**대상 경로:** `{item['target_file']}`")
                if item.get("evidence_description"):
                    st.markdown(f"**진단 근거:** {item['evidence_description']}")
                st.markdown(f"**권고 사항:** {item['recommendation_text']}")
                rem_cmd = item.get("remediation_cmd")
                if rem_cmd:
                    st.markdown("**조치 명령어:**")
                    st.code(rem_cmd, language="bash")

with tab_all:
    st.subheader("전체 점검 세부 내역")
    display_cols = [
        "code", "category", "title", "importance", "status",
        "target_file", "evidence_description", "recommendation_text",
    ]
    display_df = df[display_cols]

    styled = display_df.style.applymap(style_status, subset=["status"])
    st.dataframe(styled, use_container_width=True, height=500)
