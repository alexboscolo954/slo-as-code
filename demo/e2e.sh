#!/usr/bin/env bash
# End to end: healthy traffic -> no SLO alerts; inject 20% errors -> the page
# alert fires in Prometheus and reaches Alertmanager on the pager route, and the
# ticket for the same SLO is inhibited. (Page resolution is covered by the
# promtool tests: on a fresh Prometheus the 30m/6h pair holds the page ~30 min.)
set -euo pipefail
PROM=http://localhost:9090; AM=http://localhost:9093
fault() { docker compose exec -T app python -c "import urllib.request as u; print(u.urlopen(u.Request('http://localhost:8080/fault?$1', method='POST')).read().decode())"; }
alerts() {  # alertname severity state -> count in Prometheus
  curl -s "$PROM/api/v1/alerts" | python3 -c "
import sys, json
a = json.load(sys.stdin)['data']['alerts']
print(sum(1 for x in a if x['labels']['alertname'] == '$1' and x['labels']['severity'] == '$2' and x['state'] == '$3'))"
}
am() {  # severity state(active|suppressed) receiver -> count in Alertmanager
  curl -s "$AM/api/v2/alerts" | python3 -c "
import sys, json
print(sum(1 for a in json.load(sys.stdin)
          if a['labels']['alertname'] == 'CheckoutAvailabilityBudgetBurn'
          and a['labels']['severity'] == '$1' and a['status']['state'] == '$2'
          and '$3' in [r['name'] for r in a['receivers']]))"
}
wait_for() {  # description, command printing a number, wanted, timeout seconds
  for _ in $(seq $(( $4 / 5 ))); do
    [[ "$(eval "$2" 2>/dev/null)" == "$3" ]] && { echo "ok: $1"; return; }  # not up yet = retry
    sleep 5
  done
  echo "FAIL: $1"; curl -s "$PROM/api/v1/alerts"; exit 1
}

wait_for "prometheus scrapes checkout" \
  "curl -s '$PROM/api/v1/query?query=up%7Bjob%3D%22checkout%22%7D' | python3 -c 'import sys,json; r=json.load(sys.stdin)[\"data\"][\"result\"]; print(r[0][\"value\"][1] if r else 0)'" 1 90
sleep 60
[[ "$(alerts CheckoutAvailabilityBudgetBurn page firing)" == 0 ]] && echo "ok: healthy traffic, no page" || { echo "FAIL: page on healthy traffic"; exit 1; }

fault "error_rate=0.2"
wait_for "page fires in Prometheus (20% errors = 200x burn)" "alerts CheckoutAvailabilityBudgetBurn page firing" 1 180
wait_for "page reaches Alertmanager on the pager route" "am page active pager" 1 60
wait_for "ticket fires in Prometheus too" "alerts CheckoutAvailabilityBudgetBurn ticket firing" 1 120
wait_for "ticket is inhibited by the page" "am ticket suppressed tickets" 1 60
fault "error_rate=0"
echo "e2e ok"
