# Runbook: SLO error budget burn

Linked from every `*BudgetBurn` alert. The alert means users are seeing errors (or
slow responses) fast enough to spend the error budget early. It does **not** mean
"something is red on a dashboard".

## 1. Page or ticket?

| `severity` | Fired by | Budget gone in | Response |
|---|---|---|---|
| `page` | 5m & 1h > 14.4x, or 30m & 6h > 6x | about 2 days (14.4x), 5 days (6x) | Now, it's user-facing |
| `ticket` | 2h & 1d > 3x, or 6h & 3d > 1x | 10 days (3x), 30 days (1x) | Within business hours |

Both windows have to agree. The long window shows the burn is real, and the short one shows it's still happening. So the page clears quickly after a fix (the 5m window drops), and a single bad minute doesn't page anyone.

## 2. Size the impact

```promql
# Current error ratio vs. objective, per SLO
slo:sli_error:ratio_rate5m{sloth_service="checkout"}
slo:objective:ratio{sloth_service="checkout"}

# How fast the budget is going (1 = exactly on budget)
slo:current_burn_rate:ratio{sloth_service="checkout"}

# Budget left in the 30-day period (1 = untouched, <0 = overspent)
slo:period_error_budget_remaining:ratio{sloth_service="checkout"}
```

## 3. Find the cause

1. **What changed?** Deploys, config, feature flags, dependency releases. Line up their timestamps with when `slo:sli_error:ratio_rate5m` rose.
2. **Where are the errors?** Break the raw SLI down: `sum by (code) (rate(http_requests_total{job="checkout"}[5m]))`. For latency, look at the histogram by route or instance.
3. **Is it us or a dependency?** Check the dependencies' own SLOs and dashboards.

## 4. Mitigate before you fix

Rolling back the last change is usually the fastest way to stop the burn. Root cause can wait until the budget stops draining.

## 5. After

If the incident spent a meaningful part of the budget, apply the [error budget policy](error-budget-policy.md).
