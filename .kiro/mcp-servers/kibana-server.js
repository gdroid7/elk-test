#!/usr/bin/env node

const { Server } = require('@modelcontextprotocol/sdk/server/index.js');
const { StdioServerTransport } = require('@modelcontextprotocol/sdk/server/stdio.js');
const { CallToolRequestSchema, ListToolsRequestSchema } = require('@modelcontextprotocol/sdk/types.js');
const { exec } = require('child_process');
const { promisify } = require('util');
const fs = require('fs').promises;
const path = require('path');

const execAsync = promisify(exec);

const ROOT_DIR = process.env.ROOT_DIR || process.cwd();
const DATA_DIR = path.join(ROOT_DIR, '.kiro/data/kibana-agent');

const ES_URL = process.env.ES_URL;
const ES_USER = process.env.ES_USER;
const ES_PASSWORD = process.env.ES_PASSWORD;
const KIBANA_URL = process.env.KIBANA_URL;
const KIBANA_USER = process.env.KIBANA_USER;
const KIBANA_PASSWORD = process.env.KIBANA_PASSWORD;

function buildCurlAuth() {
  if (ES_USER && ES_PASSWORD) {
    const auth = Buffer.from(`${ES_USER}:${ES_PASSWORD}`).toString('base64');
    return `-H "Authorization: Basic ${auth}"`;
  }
  return '';
}

function buildKibanaCurlAuth() {
  if (KIBANA_USER && KIBANA_PASSWORD) {
    const auth = Buffer.from(`${KIBANA_USER}:${KIBANA_PASSWORD}`).toString('base64');
    return `-H "Authorization: Basic ${auth}"`;
  }
  return '';
}

async function getDataViewId(indexPattern) {
  const auth = buildKibanaCurlAuth();
  const { stdout } = await execAsync(
    `curl -s ${auth} "${KIBANA_URL}/api/data_views" -H "kbn-xsrf: true" | jq -r '.data_view[] | select(.name == "${indexPattern}") | .id'`
  );
  const dataViewId = stdout.trim();
  if (!dataViewId) {
    throw new Error(`Data view not found for index pattern: ${indexPattern}. Please create it in Kibana first.`);
  }
  return dataViewId;
}

async function createDataView(indexPattern, timeField = '@timestamp') {
  const auth = buildKibanaCurlAuth();
  
  // Check if it already exists
  try {
    const existingId = await getDataViewId(indexPattern);
    return `Data view already exists with ID: ${existingId}`;
  } catch (e) {
    // Doesn't exist, create it
  }
  
  const dataViewConfig = {
    data_view: {
      title: indexPattern,
      name: indexPattern,
      timeFieldName: timeField
    }
  };
  
  const { stdout } = await execAsync(
    `curl -s -X POST ${auth} "${KIBANA_URL}/api/data_views/data_view" -H "kbn-xsrf: true" -H "Content-Type: application/json" -d '${JSON.stringify(dataViewConfig)}'`
  );
  
  const result = JSON.parse(stdout);
  if (result.data_view) {
    return `Data view created successfully with ID: ${result.data_view.id}`;
  } else {
    throw new Error(`Failed to create data view: ${JSON.stringify(result)}`);
  }
}

async function listIndices(pattern = '*') {
  const auth = buildCurlAuth();
  const { stdout } = await execAsync(
    `curl -s ${auth} "${ES_URL}/_cat/indices/${pattern}?h=index&s=index" | grep -v "^\\." | sort -u`
  );
  return stdout.trim();
}

async function discoverFields(indexPattern = '*') {
  const auth = buildCurlAuth();
  const { stdout } = await execAsync(
    `curl -s ${auth} "${ES_URL}/${indexPattern}/_mapping" | jq -r 'to_entries[] | .value.mappings.properties // {} | to_entries[] | "- \\(.key) (\\(.value.type // \\"object\\"))"' | sort -u`
  );
  return stdout.trim();
}

async function queryPreview(index, field, aggType = 'terms', timeRange = '15m') {
  const auth = buildCurlAuth();
  
  let query;
  if (aggType === 'date_histogram') {
    query = {
      size: 0,
      query: { range: { '@timestamp': { gte: `now-${timeRange}`, lte: 'now' } } },
      aggs: { data: { date_histogram: { field, fixed_interval: '1m' } } }
    };
  } else {
    query = {
      size: 0,
      query: { range: { '@timestamp': { gte: `now-${timeRange}`, lte: 'now' } } },
      aggs: { data: { [aggType]: { field, size: 10 } } }
    };
  }
  
  const { stdout } = await execAsync(
    `curl -s ${auth} "${ES_URL}/${index}/_search" -H "Content-Type: application/json" -d '${JSON.stringify(query)}'`
  );
  
  const result = JSON.parse(stdout);
  if (result.error) {
    throw new Error(result.error.reason || JSON.stringify(result.error));
  }
  
  const total = result.hits?.total?.value || result.hits?.total || 0;
  const buckets = result.aggregations?.data?.buckets || [];
  
  let output = `Total documents: ${total}\n\nPreview of results:\n`;
  buckets.slice(0, 10).forEach(b => {
    output += `  ${b.key_as_string || b.key}: ${b.doc_count} documents\n`;
  });
  if (buckets.length > 10) {
    output += `  ... and ${buckets.length - 10} more\n`;
  }
  
  return output;
}

async function generateDashboard(title, index, vizType, field, timeRange = '15m') {
  const dataViewId = await getDataViewId(index);
  const dashId = `dash-${Date.now()}`;
  const vizId = `viz-${Date.now()}`;
  
  const vizConfig = {
    attributes: {
      title: `${title} Visualization`,
      visState: JSON.stringify({
        type: vizType,
        params: { field },
        aggs: [{ type: 'count', schema: 'metric' }]
      }),
      kibanaSavedObjectMeta: {
        searchSourceJSON: JSON.stringify({ index: dataViewId, query: '*', filter: [] })
      }
    }
  };
  
  const dashConfig = {
    attributes: {
      title,
      panelsJSON: JSON.stringify([{ panelIndex: '1', gridData: { x: 0, y: 0, w: 12, h: 8 }, id: vizId }]),
      timeRestore: true,
      timeFrom: `now-${timeRange}`,
      timeTo: 'now'
    }
  };
  
  await fs.mkdir(DATA_DIR, { recursive: true });
  await fs.writeFile(path.join(DATA_DIR, `${vizId}.json`), JSON.stringify(vizConfig, null, 2));
  await fs.writeFile(path.join(DATA_DIR, `${dashId}.json`), JSON.stringify(dashConfig, null, 2));
  
  return dashId;
}

async function createDashboard(dashId) {
  const vizId = `viz-${dashId.replace('dash-', '')}`;
  const vizFile = path.join(DATA_DIR, `${vizId}.json`);
  const dashFile = path.join(DATA_DIR, `${dashId}.json`);
  
  const auth = buildKibanaCurlAuth();
  
  await execAsync(
    `curl -s -X POST "${KIBANA_URL}/api/saved_objects/visualization/${vizId}" -H "kbn-xsrf: true" -H "Content-Type: application/json" ${auth} -d @"${vizFile}"`
  );
  
  await execAsync(
    `curl -s -X POST "${KIBANA_URL}/api/saved_objects/dashboard/${dashId}" -H "kbn-xsrf: true" -H "Content-Type: application/json" ${auth} -d @"${dashFile}"`
  );
  
  return `${KIBANA_URL}/app/dashboards#/view/${dashId}`;
}

async function createAlert(name, metric, threshold, operator = 'gt', index) {
  const alertsFile = path.join(DATA_DIR, 'alerts.json');
  
  let alerts = [];
  try {
    const data = await fs.readFile(alertsFile, 'utf8');
    alerts = JSON.parse(data);
  } catch (e) {
    await fs.mkdir(DATA_DIR, { recursive: true });
  }
  
  const alertId = `alert-${Date.now()}`;
  alerts.push({
    id: alertId,
    name,
    metric,
    threshold: parseFloat(threshold),
    operator,
    index,
    enabled: true
  });
  
  await fs.writeFile(alertsFile, JSON.stringify(alerts, null, 2));
  
  return `Alert configured: ${name} (ID: ${alertId})\nMetric: ${metric} ${operator} ${threshold} on index ${index}`;
}

async function checkAlerts() {
  const alertsFile = path.join(DATA_DIR, 'alerts.json');
  
  try {
    const data = await fs.readFile(alertsFile, 'utf8');
    const alerts = JSON.parse(data);
    
    const results = [];
    for (const alert of alerts.filter(a => a.enabled)) {
      const auth = buildCurlAuth();
      const query = {
        size: 0,
        aggs: {
          metric_value: {
            avg: { field: alert.metric }
          }
        }
      };
      
      const { stdout } = await execAsync(
        `curl -s ${auth} -H "Content-Type: application/json" "${ES_URL}/${alert.index}/_search" -d '${JSON.stringify(query)}'`
      );
      
      const response = JSON.parse(stdout);
      const value = response.aggregations?.metric_value?.value || 0;
      
      let triggered = false;
      switch (alert.operator) {
        case 'gt': triggered = value > alert.threshold; break;
        case 'lt': triggered = value < alert.threshold; break;
        case 'gte': triggered = value >= alert.threshold; break;
        case 'lte': triggered = value <= alert.threshold; break;
      }
      
      if (triggered) {
        results.push(`🚨 ALERT: ${alert.name} - ${alert.metric}=${value} ${alert.operator} ${alert.threshold}`);
      }
    }
    
    return results.length > 0 ? results.join('\n') : 'No alerts triggered';
  } catch (e) {
    return 'No alerts configured';
  }
}

const server = new Server(
  { name: 'kibana-server', version: '1.0.0' },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: 'list_indices',
      description: 'List all Elasticsearch indices',
      inputSchema: {
        type: 'object',
        properties: {
          pattern: { type: 'string', description: 'Index pattern (default: *)' }
        }
      }
    },
    {
      name: 'create_data_view',
      description: 'Create a Kibana data view (index pattern) for an index',
      inputSchema: {
        type: 'object',
        properties: {
          index_pattern: { type: 'string', description: 'Index pattern name' },
          time_field: { type: 'string', description: 'Time field name (default: @timestamp)', default: '@timestamp' }
        },
        required: ['index_pattern']
      }
    },
    {
      name: 'discover_fields',
      description: 'List available fields in an Elasticsearch index',
      inputSchema: {
        type: 'object',
        properties: {
          index_pattern: { type: 'string', description: 'Index pattern (default: *)' }
        }
      }
    },
    {
      name: 'query_preview',
      description: 'Preview query results with aggregations',
      inputSchema: {
        type: 'object',
        properties: {
          index: { type: 'string', description: 'Index name' },
          field: { type: 'string', description: 'Field to aggregate' },
          agg_type: { type: 'string', description: 'Aggregation type (terms/date_histogram)', default: 'terms' },
          time_range: { type: 'string', description: 'Time range (e.g., 5m, 15m, 1h)', default: '15m' }
        },
        required: ['index', 'field']
      }
    },
    {
      name: 'generate_dashboard',
      description: 'Generate dashboard configuration files',
      inputSchema: {
        type: 'object',
        properties: {
          title: { type: 'string', description: 'Dashboard title' },
          index: { type: 'string', description: 'Index pattern' },
          viz_type: { type: 'string', description: 'Visualization type (line/bar/pie/table)' },
          field: { type: 'string', description: 'Field to visualize' },
          time_range: { type: 'string', description: 'Time range (default: 15m)' }
        },
        required: ['title', 'index', 'viz_type', 'field']
      }
    },
    {
      name: 'create_dashboard',
      description: 'Create dashboard in Kibana and return URL',
      inputSchema: {
        type: 'object',
        properties: {
          dash_id: { type: 'string', description: 'Dashboard ID from generate_dashboard' }
        },
        required: ['dash_id']
      }
    },
    {
      name: 'create_alert',
      description: 'Configure a metric alert',
      inputSchema: {
        type: 'object',
        properties: {
          name: { type: 'string', description: 'Alert name' },
          metric: { type: 'string', description: 'Metric field to monitor' },
          threshold: { type: 'number', description: 'Threshold value' },
          operator: { type: 'string', description: 'Comparison operator (gt/lt/gte/lte)', default: 'gt' },
          index: { type: 'string', description: 'Index pattern' }
        },
        required: ['name', 'metric', 'threshold', 'index']
      }
    },
    {
      name: 'check_alerts',
      description: 'Evaluate all enabled alerts and return triggered alerts',
      inputSchema: { type: 'object', properties: {} }
    }
  ]
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  try {
    const { name, arguments: args } = request.params;
    
    let result;
    switch (name) {
      case 'list_indices':
        result = await listIndices(args.pattern);
        break;
      case 'create_data_view':
        result = await createDataView(args.index_pattern, args.time_field);
        break;
      case 'discover_fields':
        result = await discoverFields(args.index_pattern);
        break;
      case 'query_preview':
        result = await queryPreview(args.index, args.field, args.agg_type, args.time_range);
        break;
      case 'generate_dashboard':
        result = await generateDashboard(args.title, args.index, args.viz_type, args.field, args.time_range);
        break;
      case 'create_dashboard':
        result = await createDashboard(args.dash_id);
        break;
      case 'create_alert':
        result = await createAlert(args.name, args.metric, args.threshold, args.operator, args.index);
        break;
      case 'check_alerts':
        result = await checkAlerts();
        break;
      default:
        throw new Error(`Unknown tool: ${name}`);
    }
    
    return { content: [{ type: 'text', text: String(result) }] };
  } catch (error) {
    return { content: [{ type: 'text', text: `Error: ${error.message}` }], isError: true };
  }
});

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch(console.error);
