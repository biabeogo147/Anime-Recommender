import os
from dotenv import load_dotenv

load_dotenv()

MODEL_NAME = "gemma-3n-e2b-it"
GOOGLE_API_KEY = os.getenv("GOOGLE_API_KEY")
HUGGINGFACEHUB_API_TOKEN = os.getenv("HUGGINGFACEHUB_API_TOKEN")
METRICS_PORT = int(os.getenv("METRICS_PORT", 8000))