# Kibana Agent Runbook

Specialized agent for creating Kibana dashboards and Slack alerts from natural language.

## Installation

### 1. Install MCP Server Dependencies

```bash
cd .kiro/mcp-servers
npm install
```

### 2. Configure Environment Variables

Create or update `.env` in project root:

```bash
ES_URL="http://localhost:9200"
KIBANA_URL="http://localhost:5601"

# Optional: If authentication is required
# ES_USER="your_username"
# ES_PASSWORD="your_password"
# KIBANA_USER="your_username"
# KIBANA_PASSWORD="your_password"

# For Slack alerts
SLACK_INCOMING_WEBHOOK_URL="https://hooks.slack.com/services/your/webhook/url"
```

### 3. Register MCP Server with Kiro CLI

Add to `~/.kiro/settings/mcp.json`:

```json
{
  "mcpServers": {
    "kibana": {
      "command": "node",
      "args": ["/absolute/path/to/.kiro/mcp-servers/kibana-server.js"],
      "env": {
        "ES_URL": "http://localhost:9200",
        "KIBANA_URL": "http://localhost:5601",
        "ROOT_DIR": "/absolute/path/to/project"
      },
      "disabled": false,
      "autoApprove": []
    }
  }
}
```

Replace `/absolute/path/to/` with your actual project path.

### 4. Restart Kiro CLI

Exit and restart your chat session to load the MCP server.

## Usage

```bash
kiro chat --agent kibana-agent
```

## Capabilities

- Create Kibana dashboards from natural language
- Configure Slack metric alerts
- Discover available fields in indices
- Generate visualization configs

## Workflow

### Creating Dashboards

1. User describes what they want to visualize
2. Agent asks for:
   - Index pattern (e.g., `logs-*`, `metrics-*`)
   - Field to visualize
   - Visualization type (line/bar/pie/table)
   - Time range (default: 15m)
3. Agent generates and creates dashboard, returns URL

**Example:**
```
User: Show error count over time
Agent: What index pattern? (e.g., logs-*)
User: logs-app-*
Agent: [Creates line chart, returns Kibana URL]
```

### Creating Alerts

1. User describes alert condition
2. Agent asks for:
   - Index pattern
   - Metric field
   - Threshold value
   - Operator (gt/lt/gte/lte)
3. Agent creates alert rule

**Example:**
```
User: Alert when CPU > 80%
Agent: What index pattern?
User: metrics-system-*
Agent: [Creates alert with gt operator at 80]
```

## MCP Tools

The agent uses these MCP tools:

- `list_indices` - List all Elasticsearch indices
- `create_data_view` - Create Kibana data view (index pattern) for an index
- `discover_fields` - List available fields in an index
- `query_preview` - Preview query results with aggregations
- `generate_dashboard` - Generate dashboard config (automatically resolves data view ID)
- `create_dashboard` - Create in Kibana, return URL
- `create_alert` - Configure metric alert
- `check_alerts` - Evaluate alerts and report triggered ones

### New Features

**Automatic Data View Resolution**: When creating dashboards, the agent automatically looks up the correct Kibana data view ID for your index. No more "Could not find the data view" errors!

**Data View Creation**: If a data view doesn't exist, use `create_data_view` to create it automatically.

## Tips

- Agent asks only essential questions
- Default time range is 15 minutes
- Provide index patterns with wildcards when needed
- Use standard operators: gt (>), lt (<), gte (≥), lte (≤)

## Requirements

- Running Kibana instance (default: http://localhost:5601)
- MCP server configured for Kibana operations
- Valid index patterns in Elasticsearch
