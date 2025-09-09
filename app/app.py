import time
import streamlit as st
from pipeline.pipeline import AnimeRecommendationPipeline
from metrics.prometheus_metrics import APP_INFO, UP, LATENCY, REQUESTS, EXCEPTIONS


@st.cache_resource
def init_pipeline():
    pl = AnimeRecommendationPipeline()
    LATENCY.observe(0.0)
    return pl


def setup_ui():
    st.set_page_config(page_title="Anime Recommender", layout="wide")
    st.title("Anime Recommender System")


if __name__=="__main__":
    # Set static info once
    APP_INFO.info({
        "app": "anime-recommender",
        "version": "1.0.0",
    })

    UP.set(1)  # App is up

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

