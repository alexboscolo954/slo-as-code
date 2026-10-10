# slo-as-code

[![ci](https://github.com/alexboscolo954/slo-as-code/actions/workflows/ci.yaml/badge.svg)](https://github.com/alexboscolo954/slo-as-code/actions/workflows/ci.yaml)

SLOs defined as code with [Sloth](https://sloth.dev), generated into Prometheus multiwindow, multi-burn-rate alerts. The alerts are **proven to work** at three levels:

1. **Unit tests** (`promtool test rules`): synthetic traffic checks that a fast burn pages, a slow burn opens a ticket, healthy traffic and zero traffic stay quiet, and the page clears once errors stop.
2. **Mutation tests**: six realistic mistakes are made on purpose (wrong objective, 4xx instead of 5xx, a latency bucket that doesn't exist, a weakened threshold, a missing short window, a missing long window). The unit tests have to fail on each one.
3. **End to end**: real Prometheus and Alertmanager in Docker Compose. Errors are injected into a running service, then the test checks that the page arrives on the pager route and that the ticket for the same SLO is inhibited.

Most SLO setups stop at "the rules load". An alert that never fires, or fires on the wrong windows, looks exactly like a healthy service.

## How it works

```
slos/checkout.yaml ──sloth generate──▶ rules/checkout.yaml ──▶ Prometheus ──▶ Alertmanager
   (SLO spec)                          (34 rules, committed)                   page / ticket
        │                                      │
        └──── CI: regenerate + git diff ───────┘  drift check: rules always match the spec
```

The demo `checkout` service has two SLOs ([`slos/checkout.yaml`](slos/checkout.yaml)):

| SLO | Objective | SLI | Budget (30 days) |
|---|---|---|---|
| availability | 99.9% | Requests without a 5xx | 0.1% of requests, about 43 min of full outage |
| latency | 99% | Requests under 250 ms (`le="0.25"` bucket) | 1% of requests |

Alerting follows the Google SRE Workbook (chapter 5, "Alerting on SLOs"). Both windows of a pair must exceed the burn rate:

| Severity | Windows | Burn rate | Budget gone in |
|---|---|---|---|
| page | 5m and 1h | 14.4× | about 2 days |
| page | 30m and 6h | 6× | 5 days |
| ticket | 2h and 1d | 3× | 10 days |
| ticket | 6h and 3d | 1× | 30 days |

## The tests

[`tests/checkout-slo.test.yaml`](tests/checkout-slo.test.yaml). Each case writes out its arithmetic, so the expected result is derived, not copied from the output.

| Case | Traffic | Expected |
|---|---|---|
| Healthy | 0.05% errors for a day | Nothing fires |
| Fast burn | A clean day, then 2% errors (20×) | No page at +10m (1h window at 0.33%). Page at +55m (1h at 1.83% > 1.44%) with no ticket yet. **Page resolves** at +70m once errors stop. |
| Slow burn | A clean day, then 0.5% errors (5×) | Never pages. Ticket at +7h, when the 3d window passes 0.1%, but not at +5h. |
| Zero traffic | No requests | No alert: the ratios are 0/0 = NaN |
| Latency fast burn | 20% of requests slower than 250 ms | Latency page at +55m |

```
$ make mutate
caught:   availability objective 99.9 -> 99
caught:   error query counts 4xx, not 5xx
caught:   latency SLI on a bucket that does not exist
caught:   page threshold 14.4x -> 30x
caught:   page short window 5m -> 1h
caught:   ticket long window 3d -> 6h
```

## End to end

[`docker-compose.yaml`](docker-compose.yaml) runs the demo service (with a fault knob), a load generator at 40 req/s, Prometheus with the generated rules, and Alertmanager with page/ticket routing and inhibition ([`demo/alertmanager.yml`](demo/alertmanager.yml)). [`demo/e2e.sh`](demo/e2e.sh) runs in CI:

```
ok: prometheus scrapes checkout
ok: healthy traffic, no page
{'error_rate': 0.2, 'slow_rate': 0.0}
ok: page fires in Prometheus (20% errors = 200x burn)
ok: page reaches Alertmanager on the pager route
ok: ticket fires in Prometheus too
ok: ticket is inhibited by the page
e2e ok
```

In CI the page reached Alertmanager about 10 s after the fault. That's fast only because the fresh Prometheus has almost no history, so the 1h window is mostly error traffic. With an hour of healthy history, 20% errors need about 4.3 minutes to push the 1h window past 1.44% (0.2 × t / 60 > 0.0144).
The unit tests cover realistic timing, where history matters.

```bash
make e2e     # needs Docker
make down
```

## Usage

```bash
make tools      # pinned sloth v0.16.0 + promtool 3.15.0 into bin/ (macOS or Linux)
make generate   # slos/ -> rules/
make verify     # drift check + promtool check + unit tests + mutation tests
```

To add an SLO, edit or add a spec in `slos/`, run `make generate`, add a test case, and commit the spec, rules and test together. CI fails if someone edits `rules/` by hand.

## Docs

- [Runbook: SLO error budget burn](docs/runbook-budget-burn.md). The alerts link here: page vs. ticket, PromQL to size the impact, where to look.
- [Error budget policy](docs/error-budget-policy.md). A template: what changes at each level of remaining budget.
- Dashboards: Sloth's published Grafana dashboards ([14348](https://grafana.com/grafana/dashboards/14348), [14643](https://grafana.com/grafana/dashboards/14643)) are built on the `slo:*` recording rules generated here. They aren't loaded in CI.
- Paging into an agent: the page route can also go to [aiops-sre-agent](https://github.com/alexboscolo954/aiops-sre-agent) as a second webhook receiver for automated triage.

## Design notes

- **Sloth instead of a custom generator.** It's a maintained, widely used tool with a readable spec. What it doesn't provide is proof that the output works, and this repo adds that.
- **Generated rules are committed.** A reviewer sees the exact PromQL that will page someone, and the drift check keeps it honest.
- **Low-traffic services are the known weak spot of burn-rate alerting.** With few requests, one error is a large ratio (noisy pages), and with none the ratio is NaN (silence). The zero-traffic test documents the second case. Common fixes are a minimum request-rate condition, synthetic probes, or counting a longer window as one event.
- **Latency as a ratio** (`count - bucket{le="0.25"}`) rather than a percentile. Ratios add up correctly across instances and windows, and percentiles don't. The SLO threshold must be an existing bucket boundary, which is what the "bucket that does not exist" mutation guards.

## License

MIT
