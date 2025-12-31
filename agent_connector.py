import os
import requests
import json
from typing import Optional, Dict, Any, Generator

class LightRAGClient:
    """
    A simple client for the LightRAG API.
    """
    
    def __init__(self, base_url: str = "http://localhost:9621", api_key: Optional[str] = None):
        """
        Initialize the client.
        
        Args:
            base_url: The base URL of the LightRAG server (e.g., "https://your-service.run.app")
            api_key: The API key for authentication (optional)
        """
        self.base_url = base_url.rstrip("/")
        self.api_key = api_key
        self.headers = {}
        if self.api_key:
            self.headers["X-API-Key"] = self.api_key
            
    def check_health(self) -> Dict[str, Any]:
        """Check if the API is running and accessible."""
        try:
            response = requests.get(f"{self.base_url}/health", headers=self.headers)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.RequestException as e:
            return {"status": "unhealthy", "error": str(e)}

    def query(self, prompt: str, mode: str = "mix") -> Dict[str, Any]:
        """
        Perform a standard RAG query.
        
        Args:
            prompt: The question or query text.
            mode: Query mode ("local", "global", "hybrid", "naive", "mix", "bypass").
                  Default is "mix".
        """
        payload = {
            "query": prompt,
            "mode": mode,
            "stream": False
        }
        
        response = requests.post(
            f"{self.base_url}/query", 
            json=payload, 
            headers=self.headers
        )
        response.raise_for_status()
        return response.json()

    def query_stream(self, prompt: str, mode: str = "mix") -> Generator[str, None, None]:
        """
        Perform a streaming RAG query.
        Yields chunks of the response text as they arrive.
        """
        payload = {
            "query": prompt,
            "mode": mode,
            "stream": True
        }
        
        response = requests.post(
            f"{self.base_url}/query/stream", 
            json=payload, 
            headers=self.headers,
            stream=True
        )
        response.raise_for_status()
        
        for line in response.iter_lines():
            if line:
                try:
                    data = json.loads(line)
                    # Handle response chunks
                    if "response" in data:
                        yield data["response"]
                    # Handle error messages
                    if "error" in data:
                        raise Exception(f"Stream error: {data['error']}")
                except json.JSONDecodeError:
                    pass

    def upload_document(self, file_path: str) -> Dict[str, Any]:
        """
        Upload a document to the knowledge base.
        """
        if not os.path.exists(file_path):
            raise FileNotFoundError(f"File not found: {file_path}")
            
        filename = os.path.basename(file_path)
        with open(file_path, "rb") as f:
            files = {"file": (filename, f)}
            response = requests.post(
                f"{self.base_url}/documents/upload",
                files=files,
                headers=self.headers  # Note: Requests handles Content-Type for multipart
            )
            
        response.raise_for_status()
        return response.json()

    def insert_text(self, text: str, source_name: str = "manual_entry") -> Dict[str, Any]:
        """
        Insert raw text into the knowledge base.
        """
        payload = {
            "text": text,
            "file_source": source_name
        }
        
        response = requests.post(
            f"{self.base_url}/documents/text",
            json=payload,
            headers=self.headers
        )
        response.raise_for_status()
        return response.json()

# Example Usage
if __name__ == "__main__":
    # configuration
    API_URL = os.environ.get("LIGHTRAG_API_URL", "https://lightrag-491993824074.northamerica-northeast2.run.app")
    API_KEY = os.environ.get("LIGHTRAG_API_KEY", "bEFB-HgLYbKABMA9_gbBVJzaFwTp-e_SkT8e0iy-1-0")
    
    client = LightRAGClient(base_url=API_URL, api_key=API_KEY)
    
    print(f"Connecting to {API_URL}...")
    health = client.check_health()
    print(f"Health Status: {health.get('status', 'unknown')}")
    
    if health.get("status") == "healthy":
        print("\nSending Test Query...")
        try:
            result = client.query("What is LightRAG?")
            print(f"Response: {result.get('response')}")
        except Exception as e:
            print(f"Query failed: {e}")
