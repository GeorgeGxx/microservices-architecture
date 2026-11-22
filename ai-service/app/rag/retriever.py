import json
import logging
import re
import unicodedata
from pathlib import Path
from typing import List, Dict, Any, Optional
from app.config import settings

logger = logging.getLogger("rag_retriever")

_STOPWORDS = {
    "a", "an", "and", "are", "best", "can", "could", "for", "find", "from",
    "give", "help", "i", "in", "is", "me", "my", "of", "or", "please", "recommend",
    "recommendation", "recommendations", "show", "the", "to", "want", "what", "with",
    "un", "una", "unos", "unas", "el", "la", "los", "las", "de", "del", "para",
    "por", "favor", "quiero", "busco", "recomienda", "recomendar", "recomendacion",
    "recomendaciones", "muestra", "dame", "mejor", "mejores",
}

_PRODUCT_INTENTS = (
    frozenset({"laptop", "laptops", "notebook", "notebooks", "computer", "computers", "macbook", "computadora", "computadoras", "portatil", "portatiles"}),
    frozenset({"mouse", "mice", "raton", "ratones"}),
    frozenset({"headphone", "headphones", "headset", "headsets", "earbud", "earbuds", "audio", "audifono", "audifonos", "auricular", "auriculares"}),
    frozenset({"keyboard", "keyboards", "teclado", "teclados"}),
    frozenset({"monitor", "monitors", "display", "displays", "pantalla", "pantallas"}),
    frozenset({"shoe", "shoes", "sneaker", "sneakers", "zapato", "zapatos", "tenis"}),
    frozenset({"kindle", "ereader", "reader", "lectores", "ebook"}),
    frozenset({"tumbler", "mug", "bottle", "termo", "vaso"}),
)


def _tokens(value: str) -> set[str]:
    normalized = unicodedata.normalize("NFKD", value.lower())
    ascii_text = normalized.encode("ascii", "ignore").decode("ascii")
    return {token for token in re.findall(r"[a-z0-9]+", ascii_text) if token not in _STOPWORDS}


class LocalRAGStore:
    def __init__(self, persist_directory: Optional[str] = None):
        self.persist_directory = persist_directory or settings.CHROMA_PERSIST_DIR
        self.documents: List[Dict[str, Any]] = []
        self._init_store()

    def _init_store(self):
        Path(self.persist_directory).mkdir(parents=True, exist_ok=True)
        cache_file = Path(self.persist_directory) / "knowledge_cache.json"
        if cache_file.exists():
            try:
                with open(cache_file, "r", encoding="utf-8") as f:
                    cached = json.load(f)
                self.documents = self._upsert_documents(cached if isinstance(cached, list) else [])
            except (json.JSONDecodeError, OSError) as exc:
                logger.warning("[RAG] Warning reading cache: %s", exc)
                self.documents = []

    @staticmethod
    def _document_key(doc: Dict[str, Any]) -> str:
        metadata = doc.get("metadata", {})
        doc_type = str(metadata.get("type", "")).lower()
        sku = str(metadata.get("sku", "")).strip().upper()
        if doc_type == "product" and sku:
            return f"product:{sku}"
        doc_id = str(doc.get("id", "")).strip()
        if doc_id:
            return f"{doc_type}:{doc_id}"
        title = str(metadata.get("title", "")).strip().casefold()
        content = str(doc.get("content", "")).strip().casefold()
        return f"{doc_type}:{title or content}"

    @classmethod
    def _upsert_documents(cls, existing: List[Dict[str, Any]], incoming: Optional[List[Dict[str, Any]]] = None) -> List[Dict[str, Any]]:
        by_key: Dict[str, Dict[str, Any]] = {}
        for doc in [*existing, *(incoming or [])]:
            if not isinstance(doc, dict):
                continue
            key = cls._document_key(doc)
            if key != ":":
                by_key[key] = doc
        return list(by_key.values())

    def add_documents(self, docs: List[Dict[str, Any]]):
        self.documents = self._upsert_documents(self.documents, docs)
        self._persist()

    def replace_documents(self, doc_type: str, docs: List[Dict[str, Any]]):
        retained = [doc for doc in self.documents if doc.get("metadata", {}).get("type") != doc_type]
        self.documents = self._upsert_documents(retained, docs)
        self._persist()

    def _persist(self):
        cache_file = Path(self.persist_directory) / "knowledge_cache.json"
        with open(cache_file, "w", encoding="utf-8") as f:
            json.dump(self.documents, f, indent=2)

    @staticmethod
    def _calculate_score(doc: Dict[str, Any], query_tokens: set[str]) -> float:
        metadata = doc.get("metadata", {})
        title = _tokens(str(metadata.get("title", "")))
        category = _tokens(str(metadata.get("category", "")))
        raw_tags = metadata.get("tags", [])
        tags = _tokens(" ".join(str(tag) for tag in raw_tags)) if isinstance(raw_tags, list) else _tokens(str(raw_tags))
        content = _tokens(str(doc.get("content", "")))
        score = 0.0
        for token in query_tokens:
            if token in title:
                score += 5.0
            if token in tags:
                score += 4.0
            if token in category:
                score += 3.0
            if token in content:
                score += 1.0
        return score

    def search(self, query: str, doc_type: Optional[str] = None, top_k: int = 3) -> List[Dict[str, Any]]:
        return self.search_documents(self.documents, query=query, doc_type=doc_type, top_k=top_k)

    @classmethod
    def search_documents(
        cls,
        documents: List[Dict[str, Any]],
        query: str,
        doc_type: Optional[str] = None,
        top_k: int = 3,
    ) -> List[Dict[str, Any]]:
        if not documents or top_k <= 0:
            return []

        query_tokens = _tokens(query)
        product_intents = [intent for intent in _PRODUCT_INTENTS if query_tokens.intersection(intent)] if doc_type == "product" else []
        scored_by_key: Dict[str, tuple[float, Dict[str, Any]]] = {}

        for doc in documents:
            metadata = doc.get("metadata", {})
            if doc_type and metadata.get("type") != doc_type:
                continue
            matching_intents = cls._matching_product_intents(metadata, product_intents) if product_intents else 0
            if product_intents and matching_intents == 0:
                continue
            score = cls._calculate_score(doc, query_tokens)
            score += matching_intents * 5.0
            if score <= 0:
                continue
            key = cls._document_key(doc)
            previous = scored_by_key.get(key)
            if previous is None or score > previous[0]:
                scored_by_key[key] = (score, doc)

        scored_docs = sorted(
            scored_by_key.values(),
            key=lambda pair: (-pair[0], str(pair[1].get("metadata", {}).get("title", "")).casefold()),
        )
        return [doc for _, doc in scored_docs[:top_k]]

    @staticmethod
    def _product_terms(metadata: Dict[str, Any]) -> set[str]:
        tags = metadata.get("tags", [])
        tag_text = " ".join(str(tag) for tag in tags) if isinstance(tags, list) else str(tags)
        return _tokens(" ".join((
            str(metadata.get("title", "")),
            str(metadata.get("category", "")),
            tag_text,
        )))

    @classmethod
    def _matching_product_intents(cls, metadata: Dict[str, Any], product_intents: List[frozenset[str]]) -> int:
        terms = cls._product_terms(metadata)
        return sum(bool(terms.intersection(intent)) for intent in product_intents)

rag_store = LocalRAGStore()
