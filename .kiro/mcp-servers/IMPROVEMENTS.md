# Kibana MCP Server Improvements

## Automatic Data View Resolution

The MCP server now automatically resolves the correct data view ID when creating dashboards.

### What was fixed:
1. **Automatic Data View Lookup**: `generateDashboard()` now calls `getDataViewId()` to find the correct data view ID for an index pattern
2. **New Tool**: `create_data_view` - Creates Kibana data views automatically if they don't exist
3. **Error Prevention**: Clear error messages when data views are missing

### How it works:
- When creating a dashboard for index `sim-db-slow-query`, the server queries Kibana's API to find the data view ID (e.g., `03-index-pattern`)
- If the data view doesn't exist, you can create it using the `create_data_view` tool
- All visualizations now use the correct data view ID automatically

### Usage:
```javascript
// Create a data view first (if needed)
create_data_view({ index_pattern: "sim-db-slow-query" })

// Generate dashboard - automatically uses correct data view ID
generate_dashboard({
  title: "My Dashboard",
  index: "sim-db-slow-query",  // Will be resolved to "03-index-pattern" automatically
  viz_type: "line",
  field: "duration_ms"
})
```

### Benefits:
- No more "Could not find the data view" errors
- Dashboards work immediately after creation
- Consistent behavior across all indices
- Self-documenting - error messages guide users to create missing data views
