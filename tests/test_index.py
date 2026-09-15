import csv
import dataclasses
import json

import pytest

from anime.data import load_documents
from anime.index import IndexValidationError, build_index, open_index
from anime.providers import HashEmbeddings


def test_catalogue_has_expected_documents(settings):
    docs = load_documents(settings.data_csv)
    assert len(docs) == 269
    assert docs[0].page_content.startswith("Title: ")
    assert docs[0].metadata["title"]


def test_fake_index_manifest(fake_index):
    manifest = json.loads((fake_index / "manifest.json").read_text())
    assert manifest["count"] == 269
    assert manifest["dim"] == 384
    assert manifest["embedding_provider"] == "fake"


def test_open_index_serves_from_writable_copy(fake_index):
    db, manifest = open_index(fake_index, HashEmbeddings())
    assert db._collection.count() == manifest["count"]
    assert len(db.similarity_search("school romance", k=4)) == 4


def test_truncated_catalogue_fails_build(tmp_path, settings):
    truncated = tmp_path / "anime.csv"
    with (
        settings.data_csv.open(encoding="utf-8", newline="") as src,
        truncated.open("w", encoding="utf-8", newline="") as dst,
    ):
        rows = list(csv.reader(src))
        csv.writer(dst).writerows(rows[:101])  # header + 100 rows
    bad = dataclasses.replace(settings, data_csv=truncated)
    with pytest.raises(IndexValidationError, match="Loaded 100 documents"):
        build_index(bad, tmp_path / "out", HashEmbeddings(), "fake")


def test_missing_columns_rejected(tmp_path, settings):
    broken = tmp_path / "broken.csv"
    broken.write_text("Name,Genres\nFoo,Action\n")
    with pytest.raises(ValueError, match="missing columns"):
        load_documents(broken)
