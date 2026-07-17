import streamlit as st
import altair as alt
from snowflake.snowpark.context import get_active_session

st.set_page_config(page_title="HCP Outreach Funnel", layout="wide")
session = get_active_session()
SEMANTIC = "CEDP_HCP_OUTREACH.SEMANTIC"

st.title("HCP Subscriber Funnel — starting at Automation Studio")
st.caption("Tracks HCPs from the moment Automation Studio picks up DE_HCP_OUTREACH onward.")

tab_funnel, tab_reasons, tab_lookup = st.tabs(["Funnel", "Where & Why", "HCP Lookup"])

with tab_funnel:
    funnel = session.table(f"{SEMANTIC}.VW_HCP_FUNNEL").to_pandas().sort_values("STEP_SEQUENCE")
    st.altair_chart(
        alt.Chart(funnel).mark_bar().encode(
            x=alt.X("CHECKPOINT_NAME:N", sort=list(funnel["CHECKPOINT_NAME"])),
            y="HCPS_AT_CHECKPOINT:Q",
            tooltip=["CHECKPOINT_NAME", "HCPS_AT_CHECKPOINT", "EXCLUDED", "FAILED", "BUILT_FROM"]),
        use_container_width=True)
    st.dataframe(funnel, use_container_width=True)
    st.divider()
    st.subheader("Reconciliation")
    st.dataframe(session.table(f"{SEMANTIC}.VW_FUNNEL_RECONCILIATION").to_pandas(), use_container_width=True)

with tab_reasons:
    st.dataframe(session.table(f"{SEMANTIC}.VW_WHERE_AND_WHY_LOST").to_pandas(), use_container_width=True)
    root_cause = session.table(f"{SEMANTIC}.VW_LOSS_ROOT_CAUSE_CATEGORY").to_pandas()
    st.altair_chart(alt.Chart(root_cause).mark_arc().encode(
        theta="HCPS_AFFECTED:Q", color="RESPONSIBLE_PARTY_TYPE:N"), use_container_width=True)

with tab_lookup:
    key = st.text_input("HCP Subscriber Key", placeholder="HCP00002")
    if key:
        st.dataframe(session.sql(
            f"SELECT * FROM {SEMANTIC}.VW_HCP_LINEAGE WHERE SUBSCRIBER_KEY = '{key.strip()}'"
        ).to_pandas(), use_container_width=True)

st.divider()
st.caption("NPI is masked per role — see 06_governance/governance_policies.sql")
