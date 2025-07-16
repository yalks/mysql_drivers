// Copyright GoFrame Author(https://goframe.org). All Rights Reserved.
//
// This Source Code Form is subject to the terms of the MIT License.
// If a copy of the MIT was not distributed with this file,
// You can obtain one at https://github.com/gogf/gf.

package mysql

import (
	"context"
	"fmt"
	"strings"

	"github.com/gogf/gf/v2/database/gdb"
)

// DoFilter handles the sql before posts it to database.
func (d *Driver) DoFilter(
	ctx context.Context, link gdb.Link, sql string, args []interface{},
) (newSql string, newArgs []interface{}, err error) {
	// First, apply core filters
	newSql, newArgs, err = d.Core.DoFilter(ctx, link, sql, args)
	if err != nil {
		return
	}

	// Extract tenant database from context
	if tenantDB, ok := ctx.Value("tenant_database").(string); ok && tenantDB != "" {
		// Inject tenant routing comment for ProxySQL
		newSql = injectTenantComment(newSql, tenantDB)
	}

	return
}

// injectTenantComment injects tenant routing comment into SQL statement
func injectTenantComment(sql, tenantDB string) string {
	// Skip if comment already exists
	if strings.Contains(sql, "/* tenant_db:") {
		return sql
	}

	// Create tenant routing comment
	comment := fmt.Sprintf("/* tenant_db:%s */ ", tenantDB)
	
	// Handle different SQL statement types
	sql = strings.TrimSpace(sql)
	
	switch {
	case strings.HasPrefix(strings.ToUpper(sql), "SELECT"):
		return comment + sql
	case strings.HasPrefix(strings.ToUpper(sql), "INSERT"):
		return comment + sql
	case strings.HasPrefix(strings.ToUpper(sql), "UPDATE"):
		return comment + sql
	case strings.HasPrefix(strings.ToUpper(sql), "DELETE"):
		return comment + sql
	case strings.HasPrefix(strings.ToUpper(sql), "REPLACE"):
		return comment + sql
	case strings.HasPrefix(strings.ToUpper(sql), "WITH"):
		return comment + sql
	default:
		// For other statements (DDL, etc.), add comment after the first word
		parts := strings.SplitN(sql, " ", 2)
		if len(parts) >= 2 {
			return parts[0] + " " + comment + parts[1]
		}
		return comment + sql
	}
}