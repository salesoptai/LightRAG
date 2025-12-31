# Technical Plan: Multi-Tenant Architecture for LightRAG

## 1. Executive Summary
This document outlines the architectural changes required to transform the LightRAG application into a multi-tenant system. The primary goal is to support multiple users with isolated data environments (workspaces) accessed via unique API keys, while minimizing changes to the core codebase to facilitate future updates from the upstream open-source project.

**Core Approach:** Use a **Proxy Pattern** with **Context-Aware Middleware**. This effectively intercepts API calls and routes them to the correct user's LightRAG instance without modifying the existing API router logic.

## 2. Architecture Design

### 2.1 Data Isolation Strategy
We will utilize LightRAG's native "workspace" concept for data isolation.
*   **Storage Path:** Each workspace creates a subdirectory in the working directory (e.g., `rag_storage/tenant_a`, `rag_storage/tenant_b`).
*   **Isolation:** All KV stores, Vector DBs, and Graph DBs are initialized within this workspace subdirectory, ensuring strict data separation.

### 2.2 User & Access Management
*   **Configuration Source:** A new `users.json` file will serve as the source of truth for tenant credentials.
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
*   maintaining a registry of active `LightRAG` instances (`Dict[workspace, LightRAG]`).
*   Lazily initializing instances upon first request.
*   Managing resource lifecycle (connections, file handles) for each tenant.

## 3. Implementation Details: The Proxy Pattern

To avoid modifying the complex and frequently changing API routers (`document_routes.py`, `query_routes.py`, etc.), we will inject a **Proxy Object** instead of a static `LightRAG` instance.

### 3.1 Components

1.  **`ContextVar` Registry**: A thread-safe global registry using Python's `contextvars` to store the `current_workspace` for the active request.
2.  **`LightRAGProxy` Class**: Implements the `LightRAG` interface but contains no state.
    *   **Delegation**: For every method call (e.g., `query()`, `insert()`) or attribute access, it retrieves the `current_workspace` from the context.
    *   **Resolution**: It calls `RagManager.get_rag(workspace)` to get the real instance.
    *   **Execution**: It forwards the call to the real instance.
3.  **`TenantMiddleware`**: A FastAPI middleware that runs before every request.
    *   Extracts Auth Token / API Key.
    *   Validates credentials against `users.json`.
    *   Sets the `current_workspace` context variable.

### 3.2 Handling Background Tasks
Background tasks in FastAPI run after the response is sent, potentially clearing the request context.
*   **Solution**: The Proxy will capture the *current* context at the moment a task is scheduled (when `rag.method` is accessed inside the route), ensuring the background thread executes against the correct workspace.

## 4. Key File Changes

| File | Status | Description |
| :--- | :--- | :--- |
| `lightrag/api/rag_manager.py` | **New** | Manages pool of LightRAG instances. |
| `lightrag/api/proxy.py` | **New** | Implements `LightRAGProxy` and context vars. |
| `lightrag/api/auth.py` | Modify | Update to load/validate against `users.json`. |
| `lightrag/api/lightrag_server.py` | Modify | Initialize `RagManager` & `Proxy`, add Middleware. |
| `users.json` | **New** | Configuration for tenants/users. |
| `lightrag/api/routers/*` | **No Change** | **Remains untouched for easy updates.** |

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
