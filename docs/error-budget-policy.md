# Error budget policy (template)

A template to adapt with your stakeholders. The SLOs only change behavior if the team has agreed in advance what happens when the budget runs out.

**SLOs covered:** everything in [`slos/`](../slos). Period: rolling 30 days.

| Budget remaining (`slo:period_error_budget_remaining:ratio`) | What happens |
|---|---|
| > 50% | Normal: ship features, run experiments |
| 25-50% | Releases need a rollback plan. The on-call reviews the top budget consumers weekly. |
| 0-25% | Only low-risk changes. Reliability work goes to the top of the backlog. |
| < 0 (exhausted) | Feature freeze for the service until the budget recovers, except security fixes and reliability work. Postmortem for every incident that used more than 20% of the budget. |

**Exceptions:** budget spent by a dependency outside the team's control, or by a declared, approved load test, can be excluded by agreement. Write the exception down.

**Review:** the SLO targets themselves are reviewed every quarter. A target that's always met with a lot of budget to spare is too loose, and one that's always missed is too tight or wrong. Either way, adjust it.
