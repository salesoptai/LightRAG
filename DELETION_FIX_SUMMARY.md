# Document Deletion Fix Summary

## Problem Identified

When deleting documents from the knowledge base, ghost entities and relationships were reappearing due to cached LLM extraction results being used during the rebuild process.

### Root Cause
1. Document deletion triggers a rebuild of affected entities/relationships
2. The rebuild uses cached LLM extraction results from `text_chunks_storage`
3. These cached results contained references to the deleted entities
4. The rebuild recreated the entities from stale cache data
5. Result: Deleted entities reappeared in the knowledge graph

## Solution Implemented

### Code Fix Applied
**File**: `lightrag/api/routers/document_routes.py` (Line 368)

**Change**: Modified the `DeleteDocRequest` model default parameter:
```python
# BEFORE (caused the issue):
delete_llm_cache: bool = Field(
    default=False,  # ❌ Cache not deleted by default
    description="Whether to delete cached LLM extraction results for the documents.",
)

# AFTER (fixes the issue):
delete_llm_cache: bool = Field(
    default=True,  # ✅ Cache now deleted by default
    description="Whether to delete cached LLM extraction results for the documents.",
)
```

### Why This Fix Works
- When `delete_llm_cache=True`, the deletion process removes LLM cache entries BEFORE rebuild
- Without stale cache data, the rebuild cannot recreate deleted entities
- Entities are properly removed from the knowledge graph
- Future document deletions will work correctly

### Merge-Friendly Design
This is a **one-line change** in a single file, making it:
- ✅ Easy to identify during future merges
- ✅ Low conflict risk (parameter default value)
- ✅ Simple to reapply if needed
- ✅ Could be proposed as PR to upstream (arguably the correct default)

## Cleaning Up Existing Ghost Data

Your "affiliate" workspace currently has ghost entities. Here's how to clean it up:

### Method: SQL Workspace Deletion (Recommended)

Since you're using PostgreSQL on Cloud SQL, the cleanest approach is to drop all workspace tables.

#### Steps:

1. **Open Google Cloud Console**
   - Go to: https://console.cloud.google.com/sql/instances
   - Click on `lightrag-postgres`
   - Click "Open Cloud Shell" (terminal icon in top right)

2. **Connect to Database**
   ```bash
   gcloud sql connect lightrag-postgres --user=lightrag_user --database=lightrag
   ```
   Enter password when prompted.

3. **Execute Deletion Commands**
   ```sql
   DROP TABLE IF EXISTS affiliate_documents CASCADE;
   DROP TABLE IF EXISTS affiliate_text_chunks CASCADE;
   DROP TABLE IF EXISTS affiliate_entities CASCADE;
   DROP TABLE IF EXISTS affiliate_relationships CASCADE;
   DROP TABLE IF EXISTS affiliate_entity_chunks CASCADE;
   DROP TABLE IF EXISTS affiliate_relation_chunks CASCADE;
   DROP TABLE IF EXISTS affiliate_full_docs CASCADE;
   DROP TABLE IF EXISTS affiliate_full_entities CASCADE;
   DROP TABLE IF EXISTS affiliate_full_relations CASCADE;
   DROP TABLE IF EXISTS affiliate_llm_response_cache CASCADE;
   ```

4. **Verify Deletion**
   ```sql
   SELECT table_name FROM information_schema.tables 
   WHERE table_schema = 'public' AND table_name LIKE 'affiliate_%';
   ```
   Should return 0 rows.

5. **Exit psql**
   ```
   \q
   ```

**Result**: Your "affiliate" workspace will be completely clean and ready for fresh documents.

## Deploying the Fix to Cloud Run

After cleaning up the workspace, you need to deploy the updated code:

### Option 1: Using Cloud Build (Recommended)
```bash
# Build and deploy from your local repository
gcloud builds submit --tag northamerica-northeast2-docker.pkg.dev/gen-lang-client-0743417261/lightrag-repo/lightrag:latest

# Update Cloud Run service with new image
gcloud run services update lightrag \
    --region=northamerica-northeast2 \
    --image=northamerica-northeast2-docker.pkg.dev/gen-lang-client-0743417261/lightrag-repo/lightrag:latest
```

### Option 2: Commit and Push to Git (If using CI/CD)
```bash
git add lightrag/api/routers/document_routes.py
git commit -m "Fix: Set delete_llm_cache default to True to prevent ghost entities"
git push origin main
```
Your CI/CD pipeline should automatically deploy the change.

## Testing the Fix

After deployment, test that deletions work correctly:

1. **Upload a test document** to the "affiliate" workspace
2. **Wait for processing** to complete
3. **Delete the document** via UI or API
4. **Verify the graph is clean**:
   - Check that entities are removed
   - Verify no ghost data reappears
5. **Check the pipeline logs** - should show:
   ```
   Successfully deleted N LLM cache entries for document doc-xxxxx
   ```

## Additional Files Created

1. **delete_affiliate_workspace.sql** - SQL script to delete workspace tables
2. **cleanup_affiliate.ps1** - PowerShell script (not used due to IPv6 issue)
3. **WORKSPACE_CLEANUP_INSTRUCTIONS.md** - Manual cleanup instructions
4. **DELETION_FIX_SUMMARY.md** - This document

## Impact Assessment

### What Changed
- ✅ Future document deletions will automatically clean LLM cache
- ✅ No more ghost entities reappearing after deletion
- ✅ Backward compatible (existing workspaces unaffected until next deletion)

### What Didn't Change
- ✅ Document insertion logic unchanged
- ✅ Query logic unchanged
- ✅ Storage backends unchanged
- ✅ API endpoints unchanged (only default parameter value)

### Performance Impact
- Negligible - cache deletion is fast
- Prevents unnecessary LLM calls for deleted data
- Overall positive impact on system cleanliness

## Next Steps

1. ✅ Code fix implemented (delete_llm_cache default = True)
2. ⏳ Clean up affiliate workspace using SQL commands above
3. ⏳ Deploy updated code to Cloud Run
4. ⏳ Test document deletion with new code
5. ✅ Monitor for any issues

## Questions?

If you encounter any issues:
1. Check Cloud Run logs: `gcloud run services logs read lightrag --region=northamerica-northeast2`
2. Verify PostgreSQL connection: Check for "Successfully deleted N LLM cache entries" in logs
3. Review pipeline status via API: `GET /documents/pipeline_status`

---

**Fix Date**: February 10, 2026
**Issue**: Ghost entities reappearing after document deletion
**Solution**: Enable LLM cache cleanup by default during document deletion
**Status**: ✅ Code fixed, ⏳ Awaiting deployment
