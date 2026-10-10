#!/usr/bin/env bash
# Tests for the tests: break the SLOs or rules in ways real mistakes would,
# and require the promtool suite to FAIL each time. A mutation that survives
# means the suite can't see that class of bug.
set -euo pipefail
cd "$(dirname "$0")/.."
SLOTH=${SLOTH:-bin/sloth}; PROMTOOL=${PROMTOOL:-bin/promtool}
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
mkdir -p "$work/rules" "$work/tests"; cp tests/checkout-slo.test.yaml "$work/tests/"
survived=0

check() {
  if "$PROMTOOL" test rules "$work/tests/checkout-slo.test.yaml" >/dev/null 2>&1; then
    echo "SURVIVED: $1"; survived=1
  else
    echo "caught:   $1"
  fi
}
spec() {  # description, sed expression applied to the SLO spec
  sed "$2" slos/checkout.yaml > "$work/spec.yaml"
  "$SLOTH" generate --no-log -i "$work/spec.yaml" -o "$work/rules/checkout.yaml"
  check "$1"
}
rules() {  # description, sed expression applied to the generated rules
  sed "$2" rules/checkout.yaml > "$work/rules/checkout.yaml"
  check "$1"
}

spec  "availability objective 99.9 -> 99"     's/objective: 99.9$/objective: 99/'
spec  "error query counts 4xx, not 5xx"       's/code=~"5.."/code=~"4.."/'
spec  "latency SLI on a bucket that does not exist" 's/le="0.25"/le="0.3"/'
rules "page threshold 14.4x -> 30x"           's/(14.4 \*/(30 */'
rules "page short window 5m -> 1h"            's/ratio_rate5m{sloth_id="checkout-requests-availability", sloth_service="checkout", sloth_slo="requests-availability"} > (14.4/ratio_rate1h{sloth_id="checkout-requests-availability", sloth_service="checkout", sloth_slo="requests-availability"} > (14.4/'
rules "ticket long window 3d -> 6h"           's/ratio_rate3d{sloth_id="checkout-requests-availability"/ratio_rate6h{sloth_id="checkout-requests-availability"/'
exit $survived
