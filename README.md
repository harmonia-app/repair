# Harmonia · repair

A red check opens a Fix on your own seat. Proven, it lands as a draft pull request.

```yaml
- uses: harmonia-app/repair@v1
  if: failure()
  with:
    key: ${{ secrets.HARMONIA_KEY }}
    check: python -m pytest -q
```

One yaml line beside your test job. One secret. Zero code in your product.

## What happens

| step | words |
|---|---|
| your check goes red | the job's command, commit and log excerpt → Harmonia |
| a pull request's run | its head commit · its own branch |
| the intake reads it | Fix · your repository · where · the proof it writes |
| attempts, on your seat | a clean sandbox at that commit · your check is the proof |
| proven | one draft pull request onto the branch that went red |
| you merge | never Harmonia · main checked after |

## Inputs

| name | required | words |
|---|---|---|
| `key` | yes | `${{ secrets.HARMONIA_KEY }}` |
| `check` | yes | the command that went red · the proof |
| `setup` | no | one shell line before every attempt · `pip install -e .[test]` |
| `log` | no | the failing log's path or excerpt |
| `service` | no | `https://api.harmonia.build` |
| `wait` | no | `true` · print the pull request when proven |
| `timeout-minutes` | no | `20` |
| `rail` | no | `runner` · attempts and checks on this job's own machine, nothing on Harmonia's metal |

## Outputs

`run` · `pull-request` · `stands` (Proven · Checked · Report · Working)

## Compute

| rail | words |
|---|---|
| `rail: runner` | your workflow's machine · free |
| your Daytona or E2B key | your key · your bill |
| Harmonia sandboxes | clean sandbox · cents per attempt · at cost |

## The price

Attempts are free. You pay when the machine hands you a proven Fix.

## The seat

Your subscription · under the provider's terms · never pooled.
