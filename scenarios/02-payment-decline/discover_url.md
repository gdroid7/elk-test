# Kibana Discover — Payment Decline

## Quick Link (IST, last 15 min)
http://localhost:5601/app/discover#/?_g=(time:(from:now-15m,to:now))&_a=(index:'sim-payment-decline',columns:!(app_level,app_message,order_id,amount,gateway,error_code),query:(language:kuery,query:'scenario:%20%22payment-decline%22'),sort:!(!('@timestamp',desc)))

## KQL Queries
| Query | What it shows |
|-------|--------------|
| `scenario: "payment-decline"` | All logs for this scenario |
| `scenario: "payment-decline" AND app_level: "ERROR"` | Errors only — declined payments and circuit breaker events |
| `scenario: "payment-decline" AND error_code: "GATEWAY_TIMEOUT"` | Gateway timeout errors — precursor to circuit breaker trip |
| `scenario: "payment-decline" AND error_code: "CIRCUIT_BREAKER_OPEN"` | Circuit breaker open events — full gateway failure |
| `scenario: "payment-decline" AND gateway: "stripe"` | Stripe gateway events only |
| `scenario: "payment-decline" AND gateway: "paypal"` | PayPal gateway events only |

## Recommended Columns
`@timestamp` · `app_level` · `app_message` · `order_id` · `amount` · `gateway` · `error_code`
