import csv
import hashlib
from pathlib import Path

from langchain_core.documents import Document

REQUIRED_COLUMNS = ("Name", "Genres", "sypnopsis")


def load_documents(csv_path: Path) -> list[Document]:
    """One document per anime; rows with any missing required field are skipped."""
    with csv_path.open(encoding="utf-8", newline="") as fh:
        reader = csv.DictReader(fh)
        missing = set(REQUIRED_COLUMNS) - set(reader.fieldnames or [])
        if missing:
            raise ValueError(f"CSV {csv_path} is missing columns: {sorted(missing)}")
        docs = []
        for row in reader:
            if any(not (row.get(col) or "").strip() for col in REQUIRED_COLUMNS):
                continue
            docs.append(
                Document(
                    page_content=f"Title: {row['Name']} Overview: {row['sypnopsis']} Genres: {row['Genres']}",
                    metadata={"title": row["Name"], "mal_id": row.get("MAL_ID", "")},
                )
            )
    return docs


def content_hash(csv_path: Path, embedding_model: str) -> str:
    digest = hashlib.sha256(csv_path.read_bytes())
    digest.update(embedding_model.encode())
    return digest.hexdigest()[:12]
