import os

import httpx
import streamlit as st

API_URL = os.getenv("ANIME_API_URL", "http://localhost:8000").rstrip("/")
TIMEOUT_S = float(os.getenv("ANIME_API_TIMEOUT_S", "60"))

st.set_page_config(page_title="Anime Recommender", layout="wide")
st.title("Anime Recommender System")

query = st.text_input("Enter your anime preferences, e.g. light hearted anime with school settings")
# Stated where the box is (design §4.2): what is typed here is sent to the model provider, and, with tracing on,
# recorded with the answer in the trace store.
st.caption("What you type is sent to the model provider (OpenAI or Google's Gemini API) and may be recorded, with the "
           "answer, for tracing.")
if query:
    with st.spinner("Fetching recommendations for you..."):
        try:
            resp = httpx.post(f"{API_URL}/recommend", json={"query": query}, timeout=TIMEOUT_S)
        except httpx.HTTPError as exc:
            st.error(f"Could not reach the recommendation API: {exc}")
        else:
            if resp.status_code == 200:
                data = resp.json()
                st.markdown("### Recommendations")
                st.markdown(data["recommendations"])
                st.caption(f"model: {data['model']} · trace: {data.get('trace_id') or 'n/a'}")
            elif resp.status_code == 422:
                st.warning("Please enter between 1 and 500 characters.")
            else:
                st.error(f"Recommendation failed ({resp.status_code}). Please try again shortly.")
