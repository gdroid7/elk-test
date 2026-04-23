 🎯 Demo Prompts (Tested & Ready)

  **Dashboard Demo 1: Payment Failures**

  Show me payment decline trends over the last 30 minutes

  What happens: Creates a line chart showing payment decline patterns from sim-payment-decline index with fields like amount, error_code, gateway

  ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

  **Dashboard Demo 2: Authentication Issues**

  Create a dashboard for authentication brute force attempts

  What happens: Generates visualization from sim-auth-brute-force index showing login attempt patterns

  ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

  **Alert Demo 1: Database Performance** ✅ (Already configured)

  Check if any database queries are slower than 2 seconds

  What happens: Runs the existing alert "DB Slow Query SLA Breach" and sends Slack notification if threshold exceeded

  ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

  **Alert Demo 2: Payment Monitoring**

  Alert me when payment amounts exceed $5000

  What happens: Creates new alert on sim-payment-decline index monitoring the amount field

  ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────