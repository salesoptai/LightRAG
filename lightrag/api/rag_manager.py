import asyncio
from typing import Dict, Any, Optional
from lightrag import LightRAG
from lightrag.api.routers.document_routes import DocumentManager
from lightrag.utils import logger

class RagManager:
    """
    Manages multiple LightRAG instances for multi-tenancy.
    """
    def __init__(self, rag_init_params: Dict[str, Any], doc_manager_params: Dict[str, Any]):
        """
        Initialize RagManager with parameters for creating LightRAG and DocumentManager instances.
        
        Args:
            rag_init_params: Dictionary of parameters to pass to LightRAG constructor (excluding workspace).
            doc_manager_params: Dictionary of parameters to pass to DocumentManager constructor (excluding workspace).
        """
        self.rag_init_params = rag_init_params
        self.doc_manager_params = doc_manager_params
        
        self.rag_instances: Dict[str, LightRAG] = {}
        self.doc_managers: Dict[str, DocumentManager] = {}
        
        self.init_locks: Dict[str, asyncio.Lock] = {}
        self.global_lock = asyncio.Lock() # For accessing init_locks

    def get_rag(self, workspace: str) -> LightRAG:
        """
        Get the LightRAG instance for a specific workspace.
        Creates it if it doesn't exist (synchronously, so might be uninitialized if not handled properly).
        """
        if workspace not in self.rag_instances:
            # This path is a fallback. Ideally ensure_tenant_initialized should be called first.
            logger.warning(f"Sync creation of RAG instance for {workspace}. Storages might not be initialized.")
            # Do NOT cache the uninitialized instance to avoid poisoning the state
            return self._create_rag(workspace)
            
        return self.rag_instances[workspace]

    def get_doc_manager(self, workspace: str) -> DocumentManager:
        """
        Get the DocumentManager instance for a specific workspace.
        """
        if workspace not in self.doc_managers:
            self.doc_managers[workspace] = self._create_doc_manager(workspace)
            
        return self.doc_managers[workspace]

    async def ensure_tenant_initialized(self, workspace: str):
        """
        Ensure that the LightRAG instance for the given workspace is created and initialized.
        This includes awaiting initialize_storages().
        """
        if workspace in self.rag_instances:
            # We assume if it's in the dict, it's initialized (or being initialized)
            # To be safer, we could track initialization status.
            return

        async with self.global_lock:
            if workspace not in self.init_locks:
                self.init_locks[workspace] = asyncio.Lock()
        
        async with self.init_locks[workspace]:
            if workspace in self.rag_instances:
                return
                
            logger.info(f"Initializing RAG instance for workspace: {workspace}")
            
            # Create instance
            rag = self._create_rag(workspace)
            
            # Initialize storages
            try:
                await rag.initialize_storages()
                # Run migrations if needed
                await rag.check_and_migrate_data()
                
                self.rag_instances[workspace] = rag
                logger.info(f"RAG instance for {workspace} initialized successfully")
                
                # Also ensure doc manager is created
                if workspace not in self.doc_managers:
                    self.doc_managers[workspace] = self._create_doc_manager(workspace)
                    
            except Exception as e:
                logger.error(f"Failed to initialize RAG instance for {workspace}: {e}")
                raise

    def _create_rag(self, workspace: str) -> LightRAG:
        """Create a new LightRAG instance with the stored parameters and specific workspace."""
        params = self.rag_init_params.copy()
        params["workspace"] = workspace
        return LightRAG(**params)

    def _create_doc_manager(self, workspace: str) -> DocumentManager:
        """Create a new DocumentManager instance with the stored parameters and specific workspace."""
        params = self.doc_manager_params.copy()
        params["workspace"] = workspace
        return DocumentManager(**params)
        
    async def finalize_all(self):
        """Finalize all initialized RAG instances."""
        for workspace, rag in self.rag_instances.items():
            try:
                logger.info(f"Finalizing storage for workspace: {workspace}")
                await rag.finalize_storages()
            except Exception as e:
                logger.error(f"Error finalizing storage for {workspace}: {e}")
