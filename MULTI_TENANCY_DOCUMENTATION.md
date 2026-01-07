# LightRAG Multi-Tenancy Implementation Documentation

## 1. Overview

This document details the changes made to the LightRAG codebase to support multi-tenancy. The system now allows multiple users (tenants) to use the same LightRAG deployment while maintaining data isolation. This is achieved through a **Proxy Pattern** with **Context-Aware Middleware**, ensuring that each request is routed to the correct, isolated workspace.

## 2. Key Architectural Components

### 2.1. Request Flow
1.  **Incoming Request**: Client sends a request with `X-API-Key` or `Authorization: Bearer <token>`.
2.  **Middleware (`tenant_middleware`)**: 
    *   Intercepts the request.
    *   Validates credentials via `AuthHandler`.
    *   Determines the `workspace` (tenant ID).
    *   Initializes the tenant's resources via `RagManager` if not ready.
    *   Sets the `current_workspace` ContextVar.
3.  **Router**: The API router invokes methods on `LightRAGProxy` or `DocumentManagerProxy` (injected dependencies).
4.  **Proxy**: The proxy checks `current_workspace` and delegates the call to the specific `LightRAG` instance for that tenant.
5.  **Storage**: The underlying storage engine (e.g., PostgreSQL) executes queries filtered by `workspace`.

### 2.2. New & Modified Files

| Component | File Path | Description |
| :--- | :--- | :--- |
| **Proxy Logic** | `lightrag/api/proxy.py` | **New**. Contains `LightRAGProxy`, `DocumentManagerProxy`, and the `current_workspace` ContextVar. |
| **Manager** | `lightrag/api/rag_manager.py` | **New**. Manages the lifecycle of `LightRAG` instances. Lazily initializes tenants and handles resource locking. |
| **Auth** | `lightrag/api/auth.py` | **Modified**. Loads users/keys from `users.json`. Validates tokens and returns the associated `workspace`. |
| **Server** | `lightrag/api/lightrag_server.py` | **Modified**. Initializes `RagManager`, sets up the `tenant_middleware`, and routes requests. |
| **Storage** | `lightrag/kg/postgres_impl.py` | **Modified**. Adds `workspace` column to tables, updates Primary Keys to `(workspace, id)`, and isolates graphs via naming conventions. |

## 3. Implementation Details

### 3.1. Authentication & User Management
*   **Source of Truth**: `users.json` (or path via `USERS_JSON_PATH`).
*   **Schema**:
    ```json
    {
      "users": [
        {
          "username": "client_a",
          "api_key": "sk-...",
          "workspace": "tenant_a"
        }
      ]
    }
    ```
*   **Mechanism**: The `AuthHandler` maps API keys to user metadata, including the `workspace` field.

### 3.2. Instance Management (`RagManager`)
*   Maintains a dictionary of active `LightRAG` instances: `Dict[workspace, LightRAG]`.
*   **Lazy Loading**: Instances are created only when a request for that tenant arrives.
*   **Concurrency**: Uses `asyncio.Lock` to ensure a tenant is initialized only once, even under concurrent requests.

### 3.3. The Proxy Pattern (`proxy.py`)
Instead of a single global `rag` object, the routers now use a `LightRAGProxy`.
*   **`_get_instance()`**: Retrieves the real `LightRAG` instance for the `current_workspace`.
*   **`__getattr__`**: dynamically forwards method calls to the active instance.
*   **Context Binding**: Provides `get_bound_instance()` for background tasks where `ContextVar` context might be lost.

### 3.4. Database Isolation (PostgreSQL)
*   **Tables**: All Key-Value and Vector tables now have a `workspace` column.
*   **Primary Keys**: Changed from `id` to `(workspace, id)` to allow the same ID (e.g., "doc_1") to exist in different workspaces.
*   **Graph Storage (AGE)**:
    *   **Default Workspace**: Uses the standard graph name (e.g., `LightRAG`).
    *   **Tenant Workspaces**: Creates separate graphs named `{workspace}_{namespace}` (e.g., `tenant_a_LightRAG`).

## 4. Usage

### 4.1. Adding a New Tenant
1.  Update `users.json` with the new user's `username`, `api_key`, and `workspace`.
2.  No restart is required if the app is configured to reload, otherwise restart the service.
3.  The first request from the new tenant will trigger the creation of their isolated storage environment (tables/graphs).

### 4.2. API Access
*   **Headers**:
    *   `X-API-Key: <api_key>`
    *   *Or* `Authorization: Bearer <jwt_token>`
*   The system automatically infers the workspace. No manual `workspace` parameter is needed in API calls.

## 5. Backward Compatibility
*   If no API key is provided or authentication is disabled, the system defaults to the `default` workspace.
*   Existing single-tenant setups continue to work as the "default" tenant.

## 6. Developer Notes
*   **Background Tasks**: When using `BackgroundTasks` in FastAPI, do **not** pass the proxy object directly if the task runs outside the request context. Use `rag.get_bound_instance()` to pass the specific tenant's instance.
*   **Migrations**: The storage implementation automatically handles schema migrations (adding `workspace` columns) upon initialization.
