import time
import streamlit as st
from dotenv import load_dotenv
from config.config import METRICS_PORT
from prometheus_client import start_http_server
from pipeline.pipeline import AnimeRecommendationPipeline
from metrics.prometheus_metrics import APP_INFO, UP, LATENCY, REQUESTS, EXCEPTIONS


@st.cache_resource
def init_metrics_server(port: int) -> bool:
    print(f"Starting Prometheus metrics server on port {METRICS_PORT}...")
    start_http_server(port)
    return True


@st.cache_resource
def init_pipeline() -> AnimeRecommendationPipeline:
    pl = AnimeRecommendationPipeline()
    LATENCY.observe(0.0)
    return pl


def setup_ui():
    st.set_page_config(page_title="Anime Recommender", layout="wide")
    st.title("Anime Recommender System")


load_dotenv()

init_metrics_server(METRICS_PORT)
APP_INFO.info({
    "app": "anime-recommender",
    "version": "1.0.0",
})
UP.set(1)

pipeline = init_pipeline()
setup_ui()

query = st.text_input("Enter your anime preferences eg. : light hearted anime with school settings")
if query:
    REQUESTS.inc()
    t0 = time.time()
    try:
        with st.spinner("Fetching recommendations for you....."):
            response = pipeline.recommend(query)
            st.markdown("### Recommendations")
            st.write(response)
    except Exception as e:
        EXCEPTIONS.inc()
        st.error(f"Recommendation failed: {e}")
    finally:
        LATENCY.observe(time.time() - t0)