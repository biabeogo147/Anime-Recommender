"""Build the Chroma index at image build time and fail loudly if it is incomplete.

    python -m anime.index build --out /index [--embeddings hf|fake]
"""

import argparse
import json
import logging
import shutil
import sys
import tempfile
import time
from pathlib import Path

from langchain_chroma import Chroma
from langchain_core.embeddings import Embeddings

from anime.config import Settings, get_settings
from anime.data import content_hash, load_documents
from anime.log import configure_logging
from anime.providers import get_embeddings

logger = logging.getLogger(__name__)

COLLECTION = "anime"
MANIFEST = "manifest.json"


class IndexValidationError(RuntimeError):
    pass


def build_index(settings: Settings, out_dir: Path, embeddings: Embeddings, provider: str) -> dict:
    started = time.monotonic()
    docs = load_documents(settings.data_csv)
    if len(docs) != settings.expected_docs:
        raise IndexValidationError(
            f"Loaded {len(docs)} documents from {settings.data_csv}, expected {settings.expected_docs}"
        )
    if out_dir.exists():
        shutil.rmtree(out_dir)
    db = Chroma.from_documents(docs, embeddings, collection_name=COLLECTION, persist_directory=str(out_dir))
    count = db._collection.count()
    if count != settings.expected_docs:
        raise IndexValidationError(f"Index holds {count} vectors, expected {settings.expected_docs}")

    manifest = {
        "content_hash": content_hash(settings.data_csv, settings.embedding_model_name),
        "count": count,
        "dim": len(embeddings.embed_query("dimension probe")),
        "embedding_provider": provider,
        "embedding_model": settings.embedding_model_name,
        "build_duration_s": round(time.monotonic() - started, 1),
        "built_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    (out_dir / MANIFEST).write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    logger.info("Built index: %s", manifest)
    return manifest


def open_index(index_dir: Path, embeddings: Embeddings) -> tuple[Chroma, dict]:
    """Chroma writes to its sqlite file even on reads, so serve from a writable copy of the baked index."""
    manifest_path = index_dir / MANIFEST
    if not manifest_path.exists():
        raise IndexValidationError(f"No index manifest in {index_dir}")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    working = Path(tempfile.mkdtemp(prefix="chroma-"))
    shutil.copytree(index_dir, working, dirs_exist_ok=True)
    db = Chroma(collection_name=COLLECTION, persist_directory=str(working), embedding_function=embeddings)
    return db, manifest


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(prog="python -m anime.index")
    parser.add_argument("command", choices=["build"])
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--embeddings", choices=["hf", "fake"], default="hf")
    args = parser.parse_args(argv)

    settings = get_settings()
    configure_logging(settings.log_level)
    try:
        build_index(settings, args.out, get_embeddings(settings, args.embeddings), args.embeddings)
    except Exception:
        logger.exception("Index build failed")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
