
import os
import asyncio
import cProfile
import pstats
import time
from lightrag import LightRAG, QueryParam
from lightrag.llm.openai import openai_complete_if_cache, openai_embed
from lightrag.utils import setup_logger
import logging

# Configure logging to show timestamps and level
setup_logger("lightrag", level="INFO")
logger = logging.getLogger("lightrag")

async def profile_query():
    # --- Configuration ---
    from dotenv import load_dotenv
    load_dotenv()
    
    # Environment variables match your production setup
    WORKING_DIR = os.getenv("WORKING_DIR", "./rag_storage")
    WORKSPACE = os.getenv("LIGHTRAG_WORKSPACE", "affiliate")
    
    # LLM Settings
    LLM_MODEL = os.getenv("LLM_MODEL", "gpt-4o-mini")
    
    # Initialize LightRAG
    async def llm_model_func(
        prompt, system_prompt=None, history_messages=None, **kwargs
    ):
        return await openai_complete_if_cache(
            LLM_MODEL,
            prompt,
            system_prompt=system_prompt,
            history_messages=history_messages,
            api_key=os.getenv("LLM_BINDING_API_KEY"),
            **kwargs
        )

    async def embedding_func(texts, **kwargs):
        return await openai_embed(
            texts,
            model=os.getenv("EMBEDDING_MODEL", "text-embedding-3-large"),
            api_key=os.getenv("EMBEDDING_BINDING_API_KEY"),
            embedding_dim=int(os.getenv("EMBEDDING_DIM", "1536")),
            **kwargs
        )

    logger.info(f"Initializing LightRAG with workspace: {WORKSPACE}")
    
    rag = LightRAG(
        working_dir=WORKING_DIR,
        workspace=WORKSPACE,
        llm_model_func=llm_model_func,
        embedding_func=embedding_func,
        kv_storage=os.getenv("LIGHTRAG_KV_STORAGE", "JsonKVStorage"),
        doc_status_storage=os.getenv("LIGHTRAG_DOC_STATUS_STORAGE", "JsonDocStatusStorage"),
        vector_storage=os.getenv("LIGHTRAG_VECTOR_STORAGE", "NanoVectorDBStorage"),
        graph_storage=os.getenv("LIGHTRAG_GRAPH_STORAGE", "NetworkXStorage")
    )
    
    # Initialize storages
    await rag.initialize_storages()

    # --- Query to Profile ---
    query_text = "foundation plan"
    query_param = QueryParam(mode="hybrid", stream=False)

    logger.info(f"Starting profiled query: '{query_text}' in mode: '{query_param.mode}'")
    
    # Start Profiling
    profiler = cProfile.Profile()
    profiler.enable()
    
    start_time = time.time()
    try:
        # Note: using aquery_llm to get complete results including raw_data
        result = await rag.aquery(query_text, param=query_param)
        end_time = time.time()
        
        profiler.disable()
        
        print("\n" + "="*50)
        print(f"QUERY COMPLETED IN: {end_time - start_time:.2f} seconds")
        print("="*50)
        print(f"RESPONSE CONTENT PREVIEW: {str(result)[:200]}...")
        
        # Print Top 30 stats
        stats = pstats.Stats(profiler).sort_stats('cumulative')
        stats.print_stats(30)
        
    except Exception as e:
        logger.error(f"Query failed: {e}")
        import traceback
        traceback.print_exc()
    finally:
        await rag.finalize_storages()

if __name__ == "__main__":
    asyncio.run(profile_query())
