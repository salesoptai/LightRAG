from contextvars import ContextVar
from typing import Any
from lightrag import LightRAG
from lightrag.api.routers.document_routes import DocumentManager

# Context variable to store the current workspace
current_workspace: ContextVar[str] = ContextVar("current_workspace", default="default")

class LightRAGProxy:
    """
    Proxy for LightRAG that delegates calls to the correct instance based on the current workspace.
    """
    def __init__(self, rag_manager):
        self.rag_manager = rag_manager

    def _get_instance(self) -> LightRAG:
        workspace = current_workspace.get()
        return self.rag_manager.get_rag(workspace)

    def __getattr__(self, name: str) -> Any:
        return getattr(self._get_instance(), name)
        
    def get_bound_instance(self) -> LightRAG:
        """
        Returns the actual LightRAG instance for the current context.
        Useful for passing to background tasks where context might be lost.
        """
        return self._get_instance()

class DocumentManagerProxy:
    """
    Proxy for DocumentManager that delegates calls to the correct instance based on the current workspace.
    """
    def __init__(self, rag_manager):
        self.rag_manager = rag_manager

    def _get_instance(self) -> DocumentManager:
        workspace = current_workspace.get()
        return self.rag_manager.get_doc_manager(workspace)

    def __getattr__(self, name: str) -> Any:
        return getattr(self._get_instance(), name)

    def get_bound_instance(self) -> DocumentManager:
        """
        Returns the actual DocumentManager instance for the current context.
        """
        return self._get_instance()
