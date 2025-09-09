import os
from dotenv import load_dotenv
from config.config import METRICS_PORT
from prometheus_client import start_http_server

if __name__ == "__main__":
    load_dotenv()

    print(f"Starting Prometheus metrics server on port {METRICS_PORT}...")
    start_http_server(METRICS_PORT)

    print("Starting Streamlit app on port 8501...")
    os.system("streamlit run app/app.py --server.port=8501 --server.address=0.0.0.0 --server.headless=true")