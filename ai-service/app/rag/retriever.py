import json
import logging
from pathlib import Path
from typing import List, Dict, Any, Optional
from app.config import settings

logger = logging.getLogger("rag_retriever")


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
                    self.documents = json.load(f)
            except (json.JSONDecodeError, OSError) as exc:
                logger.warning("[RAG] Warning reading cache: %s", exc)
                self.documents = []

    def add_documents(self, docs: List[Dict[str, Any]]):
        self.documents.extend(docs)
        cache_file = Path(self.persist_directory) / "knowledge_cache.json"
        with open(cache_file, "w", encoding="utf-8") as f:
            json.dump(self.documents, f, indent=2)

    @staticmethod
    def _calculate_score(doc: Dict[str, Any], query_tokens: set) -> float:
        content = doc.get("content", "").lower()
        title = doc.get("metadata", {}).get("title", "").lower()
        tags = " ".join(doc.get("metadata", {}).get("tags", [])).lower()

        score = 0.0
        for token in query_tokens:
            if len(token) <= 2:
                continue
            if token in title:
                score += 3.0
            if token in tags:
                score += 2.0
            if token in content:
                score += 1.0
        return score

    def search(self, query: str, doc_type: Optional[str] = None, top_k: int = 3) -> List[Dict[str, Any]]:
        if not self.documents:
            return []

        query_tokens = set(query.lower().split())
        scored_docs = []

        for doc in self.documents:
            if doc_type and doc.get("metadata", {}).get("type") != doc_type:
                continue
            score = self._calculate_score(doc, query_tokens)
            scored_docs.append((score, doc))

        scored_docs.sort(key=lambda x: x[0], reverse=True)
        return [doc for score, doc in scored_docs[:top_k]]


rag_store = LocalRAGStore()
