# Technical Plan: Multi-Tenant Architecture for LightRAG

## 1. Executive Summary
This document outlines the architectural changes required to transform the LightRAG application into a multi-tenant system. The primary goal is to support multiple users with isolated data environments (workspaces) accessed via unique API keys, while minimizing changes to the core codebase to facilitate future updates from the upstream open-source project.

**Core Approach:** Use a **Proxy Pattern** with **Context-Aware Middleware**. This intercepts API calls and routes them to the correct user's `LightRAG` instance and `DocumentManager` without modifying the existing API router logic.

## 2. Architecture Design

### 2.1 Data Isolation Strategy
We will utilize LightRAG's native "workspace" concept for data isolation across all storage backends.

*   **Production Database (PostgreSQL):** The `PG*` storage implementations (`PGKVStorage`, `PGVectorStorage`, etc.) already support a `workspace` column. We will ensure the `LightRAG` instance is initialized with the correct workspace, which propagates to all SQL queries.
*   **File Storage (Local/Dev):** For local development using JSON/NanoVectorDB, each workspace creates a subdirectory in the working directory (e.g., `rag_storage/tenant_a`).
*   **Document Input:** Uploaded files will be isolated in tenant-specific subdirectories (e.g., `inputs/tenant_a`) using a proxied `DocumentManager`.

### 2.2 User & Access Management
*   **Configuration Source:** A new `users.json` file will serve as the source of truth for tenant credentials. In production, this file should be mounted via Google Secret Manager.
*   **Schema:**
    ```json
    {
      "users": [
        {
          "username": "client_a",
          "password": "hashed_secret_or_plain", 
          "api_key": "sk-client-a-key-123",
          "workspace": "tenant_a"
        }
      ]
    }
    ```
*   **Authentication:** The system will validate requests via Bearer Token (JWT) or `X-API-Key`. Successful validation resolves to a specific `workspace` identifier.

### 2.3 Instance Management (RagManager)
A new singleton component, `RagManager`, will be responsible for:
*   Maintaining a registry of active `LightRAG` instances (`Dict[workspace, LightRAG]`).
*   Lazily initializing instances upon first request.
*   Managing resource lifecycle (connections, file handles) for each tenant.

### 2.4 Document Management Isolation
A `DocumentManagerProxy` will be introduced to handle tenant-specific file operations.
*   It intercepts calls to `scan_directory` and file paths.
*   It resolves the `input_dir` dynamically based on the current tenant (e.g., `inputs/{workspace}`).

## 3. Implementation Details: The Proxy Pattern

To avoid modifying the complex and frequently changing API routers (`document_routes.py`, `query_routes.py`, etc.), we will inject **Proxy Objects** (`LightRAGProxy` and `DocumentManagerProxy`) instead of static instances.

### 3.1 Components

1.  **`ContextVar` Registry**: A thread-safe global registry using Python's `contextvars` to store the `current_workspace` for the active request.
2.  **`LightRAGProxy` Class**: Implements the `LightRAG` interface but contains no state.
    *   **Delegation**: For every method call, it retrieves the `current_workspace`.
    *   **Resolution**: Calls `RagManager.get_rag(workspace)` to get the real instance.
    *   **Execution**: Forwards the call to the real instance.
3.  **`DocumentManagerProxy` Class**: Similar to above, but manages `DocumentManager` instances to ensure file uploads go to the correct tenant directory.
4.  **`TenantMiddleware`**: A FastAPI middleware that runs before every request.
    *   Extracts Auth Token / API Key.
    *   Validates credentials against `users.json`.
    *   Sets the `current_workspace` context variable.

### 3.2 Handling Background Tasks (Context Binding)
Background tasks in FastAPI (like `background_tasks.add_task`) run after the response is sent, at which point the request context (and `ContextVar`) is often cleared or invalid.

*   **Problem**: Passing the global `Proxy` object to a background task helper function (e.g., `pipeline_index_file(rag, ...)`) fails because the helper function accesses the proxy *inside* the background thread, where the context is lost.
*   **Solution**: The Proxy must support **Context Binding**.
    *   We will modify the router calls to pass a "bound" instance to background tasks.
    *   **Mechanism**: The `LightRAGProxy` will implement a method `get_bound_instance()` (or similar) that resolves the *current* tenant's real `LightRAG` instance *during the request*.
    *   **Router Change**: Slight modifications to `document_routes.py` may be required to pass `rag.get_bound_instance()` instead of `rag` to `background_tasks.add_task`. Alternatively, we can wrap `BackgroundTasks` to automatically capture and propagate context. *Decision: We will attempt to wrap the task function with a context-preserving decorator to minimize router changes.*

## 4. Key File Changes

| File | Status | Description |
| :--- | :--- | :--- |
| `lightrag/api/rag_manager.py` | **New** | Manages pool of `LightRAG` and `DocumentManager` instances. |
| `lightrag/api/proxy.py` | **New** | Implements `LightRAGProxy`, `DocumentManagerProxy`, and context vars. |
| `lightrag/api/auth.py` | Modify | Update to load/validate against `users.json`. |
| `lightrag/api/lightrag_server.py` | Modify | Initialize `RagManager` & Proxies, add Middleware. |
| `users.json` | **New** | Configuration for tenants/users. |
| `lightrag/api/routers/document_routes.py` | Minimal Change | May need slight update to support background task context propagation if decorator approach isn't sufficient. |

## 5. Request Flow

1.  **Client Request**: `POST /query` with Header `X-API-Key: sk-client-a...`
2.  **Middleware**:
    *   Validates key.
    *   Identifies workspace: `tenant_a`.
    *   Sets `ContextVar(workspace="tenant_a")`.
3.  **Router**: Calls `rag.query(...)`. `rag` is the `LightRAGProxy`.
4.  **Proxy**:
    *   Reads `ContextVar` -> "tenant_a".
    *   Calls `RagManager.get_rag("tenant_a")`.
    *   Receives `LightRAG` instance for Tenant A.
    *   Delegates `query(...)` to Tenant A's instance.
5.  **Response**: Returned to client.

## 6. Backward Compatibility
*   If no `users.json` exists or no API key is provided (and auth is off), the system defaults to the `default` workspace, mimicking current behavior.
*   Existing environment variables (`WORKSPACE`, `LLM_BINDING`) continue to serve as global defaults for new instances.

## 7. Next Steps for Team
1.  **Review**: Validate that the Proxy Pattern aligns with long-term maintenance goals.
2.  **Security**: Ensure `users.json` is stored securely (e.g., mounted secret in K8s/Docker).
3.  **Resources**: Monitor memory usage as multiple LightRAG instances (and their vector/graph indices) will be loaded into memory simultaneously.
