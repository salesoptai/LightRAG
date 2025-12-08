# LightRAG Cloud Run Deployment Verification Checklist

Use this checklist to verify your Cloud Run + PostgreSQL deployment is working correctly.

## ✅ Pre-Deployment Checklist

### Cloud SQL Setup
- [ ] Cloud SQL PostgreSQL instance created
- [ ] Instance tier appropriate for workload (db-f1-micro for testing, db-custom for production)
- [ ] Private IP enabled, public IP disabled
- [ ] pgvector extension enabled (`cloudsql.enable_pgvector=on`)
- [ ] Database `lightrag` created
- [ ] User `lightrag_user` created with strong password
- [ ] Extensions installed: `vector`, `uuid-ossp`
- [ ] User permissions granted on schema and tables

### Secret Manager Setup
- [ ] `lightrag-postgres-password` secret created
- [ ] `lightrag-openai-api-key` secret created (or your LLM provider)
- [ ] `lightrag-embedding-api-key` secret created
- [ ] Service account has `secretmanager.secretAccessor` role

### Docker Image
- [ ] Artifact Registry repository created
- [ ] Docker image built successfully
- [ ] Docker image pushed to Artifact Registry
- [ ] Image tagged correctly (e.g., `latest` or version number)

### Environment Configuration
- [ ] `.env.cloudrun.postgres` file reviewed
- [ ] `POSTGRES_HOST` set to Cloud SQL private IP
- [ ] `POSTGRES_PASSWORD` matches the secret
- [ ] `LIGHTRAG_*_STORAGE` variables set to PostgreSQL backends
- [ ] LLM API keys configured
- [ ] Embedding API keys configured
- [ ] `WORKSPACE` variable set (e.g., `production`)

---

## 🚀 Deployment Verification

### Cloud Run Service
- [ ] Service deployed successfully
- [ ] Cloud SQL instance connected (`--add-cloudsql-instances`)
- [ ] Environment variables configured
- [ ] Secrets mounted correctly
- [ ] Service account has necessary permissions
- [ ] Memory allocation sufficient (minimum 2Gi recommended)
- [ ] CPU allocation sufficient (minimum 2 CPUs recommended)
- [ ] Timeout set appropriately (300+ seconds for document processing)

### Network Configuration
- [ ] Service can reach Cloud SQL (private IP connectivity)
- [ ] Service can reach external APIs (LLM providers)
- [ ] CORS configured if accessing from different domains

---

## 🧪 Functional Testing

### Test 1: Health Check
```bash
curl https://YOUR-CLOUD-RUN-URL/health
```
- [ ] Returns `{"status": "healthy"}` or similar
- [ ] Response time < 5 seconds

### Test 2: Web UI Access
- [ ] Web UI loads in browser
- [ ] Login page appears (if authentication enabled)
- [ ] No console errors in browser developer tools
- [ ] UI is responsive and functional

### Test 3: Database Connection
Check Cloud Run logs:
```bash
gcloud run services logs read lightrag --region=REGION --limit=50
```
- [ ] No PostgreSQL connection errors
- [ ] See "Initialized PGKVStorage" message
- [ ] See "Initialized PGDocStatusStorage" message
- [ ] See "Initialized PGGraphStorage" message
- [ ] See "Initialized PGVectorStorage" message

### Test 4: Document Upload
- [ ] Upload a small text document (< 1MB)
- [ ] Processing completes without errors
- [ ] Status shows "completed" or "processed"
- [ ] No timeout errors in Cloud Run logs

### Test 5: Database Verification
Connect to PostgreSQL:
```bash
gcloud sql connect INSTANCE_NAME --user=lightrag_user --database=lightrag
```

Check tables:
```sql
-- List all tables
\dt

-- Expected tables (with workspace prefix):
-- production_documents
-- production_entities
-- production_relationships
-- production_chunks
-- production_text_chunks
-- production_llm_query_cache
```
- [ ] Tables exist with correct workspace prefix
- [ ] At least one document in `production_documents`
- [ ] Entities extracted in `production_entities`
- [ ] Vector embeddings stored

### Test 6: Query Functionality
- [ ] Submit a query through the UI
- [ ] Query returns relevant results
- [ ] Response time acceptable (< 30 seconds)
- [ ] Results include source attribution

### Test 7: Data Persistence (CRITICAL)
- [ ] Upload a document and note its ID
- [ ] Restart Cloud Run service:
  ```bash
  gcloud run services update lightrag --region=REGION --update-env-vars="TEST_RESTART=$(date +%s)"
  ```
- [ ] Wait for service to restart
- [ ] Refresh web UI
- [ ] Previously uploaded document still visible
- [ ] Query the document - it returns results
- [ ] **SUCCESS**: Data persists across restarts!

---

## 🔍 Performance Testing

### Upload Performance
- [ ] Small file (< 1MB): Processes in < 2 minutes
- [ ] Medium file (1-10MB): Processes in < 10 minutes
- [ ] Large file (10-50MB): Processes in < 30 minutes
- [ ] No timeout errors during processing

### Query Performance
- [ ] Simple queries: Response in < 5 seconds
- [ ] Complex queries: Response in < 15 seconds
- [ ] Graph visualization loads: < 10 seconds

### Database Performance
Check PostgreSQL metrics:
```bash
gcloud sql operations list --instance=INSTANCE_NAME
```
- [ ] CPU usage < 70% during normal operations
- [ ] Memory usage < 80%
- [ ] Connection count < max_connections limit
- [ ] Query response times acceptable

---

## 🔒 Security Verification

### Authentication
- [ ] Cannot access API without authentication (if enabled)
- [ ] JWT tokens expire correctly
- [ ] Password complexity requirements met

### Database Security
- [ ] PostgreSQL only accessible via private IP
- [ ] No public IP assigned to Cloud SQL instance
- [ ] SSL connections configured (if required)
- [ ] Database credentials stored in Secret Manager only

### API Security
- [ ] API keys not exposed in logs
- [ ] HTTPS enforced (Cloud Run default)
- [ ] CORS properly configured
- [ ] Rate limiting configured (if needed)

---

## 📊 Monitoring Setup

### Cloud Run Monitoring
- [ ] Cloud Run metrics visible in Google Cloud Console
- [ ] Request count tracked
- [ ] Error rate tracked
- [ ] Latency metrics available
- [ ] Container instance count visible

### Cloud SQL Monitoring
- [ ] Cloud SQL metrics visible
- [ ] CPU utilization tracked
- [ ] Memory utilization tracked
- [ ] Connection count tracked
- [ ] Query performance insights enabled

### Alerts Configured
- [ ] Cloud Run error rate > 5% alert
- [ ] Cloud SQL CPU > 80% alert
- [ ] Cloud SQL connections > 80% of max alert
- [ ] Cloud Run timeout alert
- [ ] Budget alerts configured

### Logging
- [ ] Cloud Run logs streaming correctly
- [ ] PostgreSQL logs accessible
- [ ] Error logs categorized properly
- [ ] Log retention policy configured

---

## 🛠️ Troubleshooting Verification

### Common Issues Tested
- [ ] Service restarts gracefully
- [ ] Database connection retries work
- [ ] Handles high concurrent requests
- [ ] Recovers from temporary network issues
- [ ] Handles large documents without crashing

### Error Handling
- [ ] Invalid file uploads handled gracefully
- [ ] API errors return meaningful messages
- [ ] Database connection errors logged clearly
- [ ] UI shows user-friendly error messages

---

## 💰 Cost Verification

### Review Current Costs
- [ ] Cloud SQL instance cost reviewed
- [ ] Cloud Run usage cost reviewed
- [ ] Storage costs reviewed
- [ ] Network egress costs reviewed
- [ ] Total monthly estimate acceptable

### Cost Optimization
- [ ] Cloud Run min-instances = 0 (scales to zero when idle)
- [ ] Cloud SQL tier appropriate for load
- [ ] Automated backups configured but not excessive
- [ ] No unnecessary data retention
- [ ] Budget alerts configured

---

## 📈 Scalability Testing

### Load Testing (Optional)
- [ ] Multiple concurrent document uploads work
- [ ] Multiple concurrent queries work
- [ ] Cloud Run scales up automatically
- [ ] Database handles increased connection load
- [ ] Performance remains acceptable under load

### Scaling Configuration
- [ ] max-instances set appropriately
- [ ] min-instances = 0 or 1 based on needs
- [ ] Database connection pool sized correctly
- [ ] Cloud SQL tier can handle peak load

---

## ✨ Final Verification

### Production Readiness
- [ ] All tests passed successfully
- [ ] Data persists across restarts ✓ (MOST IMPORTANT)
- [ ] Performance acceptable for use case
- [ ] Security requirements met
- [ ] Monitoring and alerts configured
- [ ] Backup and recovery tested
- [ ] Documentation reviewed and understood
- [ ] Team trained on operations

### Sign-Off
- [ ] Deployment verified by: ________________
- [ ] Date verified: ________________
- [ ] Issues identified: ________________
- [ ] Ready for production: YES / NO

---

## 🎉 Success Criteria

Your deployment is successful when:

1. ✅ **Data Persistence**: Documents uploaded survive service restarts
2. ✅ **Functionality**: All features work (upload, query, visualization)
3. ✅ **Performance**: Response times meet requirements
4. ✅ **Security**: No credentials exposed, proper authentication
5. ✅ **Monitoring**: Metrics and logs flowing correctly
6. ✅ **Scalability**: Service scales appropriately with load

---

## 📞 Getting Help

If you encounter issues:

1. **Check Logs**:
   ```bash
   gcloud run services logs read lightrag --region=REGION --limit=100
   ```

2. **Check Database**:
   ```bash
   gcloud sql connect INSTANCE_NAME --user=lightrag_user --database=lightrag
   ```

3. **Review Documentation**:
   - `CLOUDRUN_DEPLOYMENT_GUIDE.md`
   - [LightRAG GitHub Issues](https://github.com/HKUDS/LightRAG/issues)

4. **Common Solutions**:
   - Connection issues: Check VPC and Cloud SQL connection
   - Permission errors: Review IAM roles and Secret Manager access
   - Performance issues: Increase Cloud SQL tier or Cloud Run resources
   - Data not persisting: Verify PostgreSQL storage backends configured

---

## 📝 Notes

Use this space to document your specific configuration:

- **Project ID**: ________________
- **Region**: ________________
- **Cloud SQL Instance**: ________________
- **Cloud Run Service URL**: ________________
- **Workspace Name**: ________________
- **Special Configurations**: ________________
- **Known Issues**: ________________
