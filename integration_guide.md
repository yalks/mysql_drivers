# Integration Guide: Enhanced MySQL Driver for Admin-APIv3

## Overview

This guide explains how to integrate the enhanced MySQL driver with context-based SQL comment injection into the admin-apiv3 project for seamless multi-tenant database routing.

## Integration Steps

### 1. Replace Official MySQL Driver

Replace the official GoFrame MySQL driver with the enhanced version:

```bash
# Backup original driver
cp $GOPATH/src/github.com/gogf/gf/v2/contrib/drivers/mysql/mysql_do_filter.go \
   $GOPATH/src/github.com/gogf/gf/v2/contrib/drivers/mysql/mysql_do_filter.go.bak

# Copy enhanced driver
cp /Users/song/Desktop/game/mysql_drivers/mysql_do_filter.go \
   $GOPATH/src/github.com/gogf/gf/v2/contrib/drivers/mysql/mysql_do_filter.go
```

### 2. Update Tenant Middleware

Modify the existing tenant middleware to set context values instead of executing USE commands:

```go
// File: internal/middleware/tenant_proxy_enhanced.go
package middleware

import (
    "context"
    "net/http"
    "strings"
    
    "github.com/gogf/gf/v2/frame/g"
    "github.com/gogf/gf/v2/net/ghttp"
    "github.com/gogf/gf/v2/os/glog"
)

func TenantProxyEnhanced(r *ghttp.Request) {
    // Extract tenant information from headers
    tenantHeader := r.Header.Get("X-Tenant-ID")
    if tenantHeader == "" {
        glog.Error(r.Context(), "Missing X-Tenant-ID header")
        r.Response.WriteStatus(http.StatusBadRequest, "Missing tenant information")
        return
    }

    // Validate and extract tenant info
    tenantInfo, err := extractTenantInfo(tenantHeader)
    if err != nil {
        glog.Error(r.Context(), "Invalid tenant information:", err)
        r.Response.WriteStatus(http.StatusBadRequest, "Invalid tenant information")
        return
    }

    // Set tenant database in context for enhanced driver
    ctx := context.WithValue(r.Context(), "tenant_database", tenantInfo.DatabaseName)
    r.SetCtx(ctx)

    // Log tenant routing for debugging
    glog.Info(ctx, "Tenant routing:", g.Map{
        "tenant_id": tenantInfo.Id,
        "database":  tenantInfo.DatabaseName,
        "header":    tenantHeader,
    })

    r.Middleware.Next()
}

// TenantInfo represents tenant information
type TenantInfo struct {
    Id           string
    DatabaseName string
}

// extractTenantInfo extracts tenant information from the header
func extractTenantInfo(header string) (*TenantInfo, error) {
    // Your existing tenant extraction logic
    parts := strings.Split(header, ":")
    if len(parts) != 2 {
        return nil, fmt.Errorf("invalid tenant header format")
    }

    return &TenantInfo{
        Id:           parts[0],
        DatabaseName: parts[1] + "_database",
    }, nil
}
```

### 3. Update Router Configuration

Replace the existing tenant middleware with the enhanced version:

```go
// File: internal/router/admin_v1.go
package router

import (
    "github.com/gogf/gf/v2/net/ghttp"
    "your-project/internal/middleware"
)

func bindRouter(group *ghttp.RouterGroup) {
    // Use enhanced tenant middleware
    group.Middleware(middleware.TenantProxyEnhanced)
    
    // Your existing routes...
}
```

### 4. Configure ProxySQL

Apply the enhanced ProxySQL configuration:

```bash
# Connect to ProxySQL admin interface
mysql -h 127.0.0.1 -P 6032 -u admin -p

# Apply configuration
source /Users/song/Desktop/game/mysql_drivers/proxysql-comment-routing.sql
```

### 5. Update Application Configuration

Update your database configuration to point to ProxySQL:

```yaml
# File: manifest/config/config.yaml
database:
  default:
    host: "127.0.0.1"
    port: "6033"  # ProxySQL port
    user: "root"
    pass: "root"
    name: "game"  # Default database
    type: "mysql"
    charset: "utf8mb4"
    debug: true
```

## Testing the Integration

### 1. Test Context Injection

Create a test endpoint to verify context injection:

```go
// File: internal/controller/test_tenant.go
package controller

import (
    "context"
    
    "github.com/gogf/gf/v2/frame/g"
    "github.com/gogf/gf/v2/net/ghttp"
)

func TestTenant(r *ghttp.Request) {
    ctx := r.Context()
    
    // This query will automatically include tenant routing comment
    result, err := g.DB().Ctx(ctx).Query("SELECT DATABASE() as current_db")
    if err != nil {
        r.Response.WriteJson(g.Map{
            "error": err.Error(),
        })
        return
    }
    
    r.Response.WriteJson(g.Map{
        "success": true,
        "result":  result,
        "tenant_db": ctx.Value("tenant_database"),
    })
}
```

### 2. Verify SQL Comment Injection

Monitor ProxySQL logs to verify comment injection:

```bash
# Check ProxySQL query log
tail -f /var/lib/proxysql/queries.log | grep "tenant_db"
```

Expected output:
```
/* tenant_db:aaaaa1_database */ SELECT DATABASE() as current_db
```

### 3. Test API Endpoints

```bash
# Test with tenant header
curl -H "X-Tenant-ID: aaaaa1:aaaaa1" \
     -H "Content-Type: application/json" \
     http://localhost:7999/api/v1/test-tenant

# Expected response should show routing to aaaaa1_database
```

## Performance Verification

### 1. Benchmark Comparison

```bash
# Before (USE command approach)
ab -n 1000 -c 10 -H "X-Tenant-ID: aaaaa1:aaaaa1" http://localhost:7999/api/v1/users

# After (comment injection approach)
ab -n 1000 -c 10 -H "X-Tenant-ID: aaaaa1:aaaaa1" http://localhost:7999/api/v1/users
```

### 2. Monitor Database Connections

```sql
-- Check connection pool status
SELECT * FROM stats_mysql_connection_pool;

-- Monitor query rule hits
SELECT * FROM stats_mysql_query_rules ORDER BY hits DESC;
```

## Troubleshooting

### 1. Context Not Set

**Symptom**: Queries don't include tenant comments
**Solution**: Verify middleware is setting context correctly

```go
// Debug context in middleware
glog.Debug(ctx, "Context tenant_database:", ctx.Value("tenant_database"))
```

### 2. ProxySQL Not Routing

**Symptom**: All queries go to default database
**Solution**: Check ProxySQL rule configuration

```sql
-- Verify rules are loaded
SELECT * FROM mysql_query_rules WHERE active = 1;

-- Check rule matching
SELECT * FROM stats_mysql_query_rules;
```

### 3. Performance Issues

**Symptom**: Increased query latency
**Solution**: Optimize ProxySQL configuration

```sql
-- Adjust connection pool settings
SET mysql-default_max_connections = 1000;
SET mysql-max_connections = 2000;
LOAD MYSQL VARIABLES TO RUNTIME;
```

## Migration from USE Command Approach

### 1. Remove USE Commands

```bash
# Find and remove USE command middleware
grep -r "USE \`" internal/middleware/
```

### 2. Update Existing Code

Replace direct database connections with context-aware calls:

```go
// Before
g.DB().Exec(ctx, fmt.Sprintf("USE `%s`", databaseName))
result, err := g.DB().Query("SELECT * FROM users")

// After
ctx = context.WithValue(ctx, "tenant_database", databaseName)
result, err := g.DB().Ctx(ctx).Query("SELECT * FROM users")
```

### 3. Test Migration

```bash
# Run comprehensive tests
go test ./internal/logic/... -v
go test ./internal/controller/... -v
```

## Best Practices

### 1. Context Management

- Always use `g.DB().Ctx(ctx)` for database operations
- Ensure context is properly passed through function calls
- Use context deadline for long-running operations

### 2. Error Handling

- Log tenant routing failures
- Implement fallback mechanisms
- Monitor ProxySQL health

### 3. Security

- Validate tenant headers
- Implement tenant access controls
- Audit tenant database access

## Monitoring and Alerts

### 1. ProxySQL Monitoring

```sql
-- Monitor connection health
SELECT hostgroup, srv_host, status, Queries, Bytes_sent, Bytes_recv 
FROM stats_mysql_connection_pool;

-- Track query patterns
SELECT digest_text, count_star, sum_time 
FROM stats_mysql_query_digest 
ORDER BY sum_time DESC LIMIT 10;
```

### 2. Application Metrics

```go
// Add tenant-specific metrics
var tenantQueryCounter = prometheus.NewCounterVec(
    prometheus.CounterOpts{
        Name: "tenant_queries_total",
        Help: "Total number of tenant queries",
    },
    []string{"tenant_id", "database"},
)
```

## Conclusion

This integration provides a robust, performant multi-tenant solution that:

- ✅ Eliminates connection pollution
- ✅ Maintains backward compatibility
- ✅ Provides automatic tenant routing
- ✅ Scales with your application
- ✅ Integrates seamlessly with existing code

The enhanced MySQL driver with context-based comment injection offers the best balance of performance, maintainability, and scalability for multi-tenant applications.