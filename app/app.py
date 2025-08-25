import time
import streamlit as st
from dotenv import load_dotenv
from config.config import METRICS_PORT
from prometheus_client import start_http_server
from pipeline.pipeline import AnimeRecommendationPipeline
from metrics.prometheus_metrics import APP_INFO, UP, LATENCY, REQUESTS, EXCEPTIONS


@st.cache_resource
def init_pipeline():
    t0 = time.time()
    pl = AnimeRecommendationPipeline()
    init_dur = time.time() - t0
    # Ghi nhận thời gian init như 1 observation trong histogram (tuỳ chọn)
    LATENCY.observe(init_dur * 0)  # no-op để đảm bảo metric tồn tại; có thể bỏ
    return pl


def setup_ui():
    st.set_page_config(page_title="Anime Recommender", layout="wide")
    st.title("Anime Recommender System")


if __name__=="__main__":
    load_dotenv()

    try:
        # Mở cổng /metrics trên 0.0.0.0:METRICS_PORT
        start_http_server(METRICS_PORT)
    except OSError:
        # Đã mở rồi (do rerun hoặc nhiều worker) -> bỏ qua
        pass

    # Set static info once
    APP_INFO.info({
        "app": "anime-recommender",
        "version": "1.0.0",
    })

    UP.set(1)  # app đang sống

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

