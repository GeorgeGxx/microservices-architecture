from app.rag.ingest import ingest_all
from app.rag.retriever import rag_store, LocalRAGStore


def test_rag_ingest_all(tmp_path, monkeypatch):
    store = LocalRAGStore(persist_directory=str(tmp_path))
    monkeypatch.setattr("app.rag.ingest.rag_store", store)
    store.add_documents([{
        "id": "product-OLD-MOUSE",
        "content": "Product: Stale Logitech Mouse",
        "metadata": {"type": "product", "sku": "OLD-MOUSE", "title": "Stale Logitech Mouse"},
    }])
    ingest_all()
    first_count = len(store.documents)
    ingest_all()
    assert first_count > 0
    assert len(store.documents) == first_count
    products = store.search("recommend a laptop", doc_type="product", top_k=5)
    assert [item["metadata"]["sku"] for item in products] == ["LAPTOP-PRO"]
    assert products[0]["metadata"]["rating"] == 4.9
    assert not any("Logitech" in item["metadata"].get("title", "") for item in store.documents)


def test_rag_search_product():
    results = rag_store.search("laptop pro", doc_type="product", top_k=2)
    assert len(results) > 0
    assert "laptop pro" in results[0]["content"].lower()


def test_rag_does_not_return_zero_score_or_duplicate_products(tmp_path):
    store = LocalRAGStore(persist_directory=str(tmp_path))
    item = {
        "id": "product-MOUSE-1",
        "content": "Product: Wireless Mouse\nCategory: Accessories\nTags: mouse, ergonomic",
        "metadata": {"type": "product", "sku": "MOUSE-1", "title": "Wireless Mouse", "category": "Accessories", "tags": ["mouse", "ergonomic"]},
    }
    laptop = {
        "id": "product-LAPTOP-1",
        "content": "Product: Example Laptop\nCategory: Computers & Laptops\nTags: laptop, portable",
        "metadata": {"type": "product", "sku": "LAPTOP-1", "title": "Example Laptop", "category": "Computers & Laptops", "tags": ["laptop", "portable"]},
    }
    store.add_documents([item, dict(item), laptop, dict(laptop)])
    results = store.search("Recommend a laptop", doc_type="product", top_k=5)
    assert len(results) == 1
    assert results[0]["metadata"]["sku"] == "LAPTOP-1"


def test_rag_search_policy():
    results = rag_store.search("warranty", doc_type="policy", top_k=2)
    assert len(results) > 0
    assert "warranty" in results[0]["content"].lower()


def test_rag_empty_store():
    empty_store = LocalRAGStore(persist_directory="/tmp/test_empty_rag")
    res = empty_store.search("test")
    assert res == []
