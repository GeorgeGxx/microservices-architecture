from app.rag.ingest import ingest_all
from app.rag.retriever import rag_store, LocalRAGStore


def test_rag_ingest_all():
    ingest_all()
    assert len(rag_store.documents) > 0


def test_rag_search_product():
    results = rag_store.search("macbook air", doc_type="product", top_k=2)
    assert len(results) > 0
    assert "macbook" in results[0]["content"].lower()


def test_rag_search_policy():
    results = rag_store.search("warranty", doc_type="policy", top_k=2)
    assert len(results) > 0
    assert "warranty" in results[0]["content"].lower()


def test_rag_empty_store():
    empty_store = LocalRAGStore(persist_directory="/tmp/test_empty_rag")
    res = empty_store.search("test")
    assert res == []
