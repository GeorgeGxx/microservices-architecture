import json
import logging
from pathlib import Path
from app.rag.retriever import rag_store

logger = logging.getLogger("rag_ingest")


def ingest_all():
    logger.info("[RAG] Ingesting policies and product catalog...")
    base_dir = Path(__file__).parent / "data"
    docs = []

    # 1. Ingest Policies
    policies_path = base_dir / "policies.md"
    if policies_path.exists():
        with open(policies_path, "r", encoding="utf-8") as f:
            content = f.read()

        sections = content.split("## ")
        for sec in sections:
            if not sec.strip() or sec.startswith("# AuraCommerce"):
                continue
            lines = sec.split("\n", 1)
            title = lines[0].strip()
            body = lines[1].strip() if len(lines) > 1 else ""
            docs.append({
                "id": f"policy-{title.lower().replace(' ', '-')[:30]}",
                "content": f"## {title}\n{body}",
                "metadata": {
                    "type": "policy",
                    "title": title
                }
            })

    # 2. Ingest Products Catalog
    products_path = base_dir / "products.json"
    if products_path.exists():
        with open(products_path, "r", encoding="utf-8") as f:
            products = json.load(f)
        for p in products:
            doc_text = f"Product: {p['name']}\nCategory: {p['category']}\nPrice: ${p['price']}\nRating: {p['rating']} / 5.0\nDescription: {p['description']}\nTags: {', '.join(p['tags'])}"
            docs.append({
                "id": f"product-{p['sku']}",
                "content": doc_text,
                "metadata": {
                    "type": "product",
                    "title": p["name"],
                    "sku": p["sku"],
                    "price": p["price"],
                    "category": p["category"],
                    "tags": p["tags"]
                }
            })

    rag_store.add_documents(docs)
    logger.info("[RAG] Successfully ingested %d documents into Knowledge Base.", len(docs))


if __name__ == "__main__":
    ingest_all()
