# Production migration measurements

The production implementation is available for review, but the performance gate
is **not satisfied for every workload**. Optimization stopped at the requested
design checkpoint. JavaScript destination switching exceeds the proposed 5–10%
budget on tall ASCII and long-cell tables. No shared cleanup metadata, additional
destination cache, or global cache has been added to address that gap.

Measured on 2026-10-25, macOS arm64, Dart 3.13.5, Node 26.12.1. The baseline library
and frontend are revision `6f9ed7b889e833b34cda85c889b5a02c4790288a`.
Both revisions use the same new lifecycle harness, compiler settings, and generated
inputs. Native builds use `dart compile exe`; JavaScript uses
`dart compile js -O2 --no-source-maps` and runs in Node. These are local comparison
results, not browser-interaction measurements or universal performance guarantees.

## Workloads and total work

[`benchmark_pipeline.dart`](../apps/table_web/tool/benchmark_pipeline.dart)
exercises explicit and automatic full conversion, preview alone, preview followed
by full output, repeated preview/full reads, and switching destinations after a
complete first conversion. Fixtures include quoted CSV with 30,000 ASCII rows,
2,000 rows × 100 Unicode columns, 10,000 multiline/whitespace-heavy rows, and
100 rows × five approximately 16,000-character cells. Preview limits match the web
app. Generation and console output are excluded from timings.

The harness reports the first call separately, followed by the median of five
warmed batches lasting at least 100 ms each. Selected total-work medians, in ms:

| Runtime / fixture | Operation | Before | After | Change |
| --- | --- | ---: | ---: | ---: |
| Native / tall ASCII | Preview then Slack full output | 36.95 | 29.28 | −21% |
| Native / wide Unicode | Preview then Markdown full output | 713.80 | 683.12 | −4% |
| Native / whitespace | Preview then Slack full output | 261.33 | 139.94 | −46% |
| Native / long cells | Preview then Markdown full output | 64.49 | 53.76 | −17% |
| JavaScript / tall ASCII | Preview then Slack full output | 30.50 | 34.00 | +11% |
| JavaScript / wide Unicode | Preview then Markdown full output | 204.00 | 209.00 | +2% |
| JavaScript / whitespace | Preview then Slack full output | 52.50 | 38.00 | −28% |
| JavaScript / long cells | Preview then Markdown full output | 48.33 | 52.00 | +8% |

Direct full conversions generally meet the target. An exception in this run was
explicit JavaScript whitespace-heavy CSV to Markdown, 33.67 → 37.67 ms (+12%).
Repeated reads retain the session and its complete string; they do not render
the full table again. Native destination-switching totals improved across these
fixtures. JavaScript switching needs a separate decision.

Focused JavaScript reruns confirmed the switching gap:

| Fixture | First → second destination | Before | After | Change |
| --- | --- | ---: | ---: | ---: |
| Tall ASCII | Slack → Markdown | 58.0 | 66.5 | +15% |
| Tall ASCII | Markdown → Slack | 56.0 | 66.5 | +19% |
| Long cells | Slack → Markdown | 46.0 | 63.0 | +37% |
| Long cells | Markdown → Slack | 46.0 | 61.5 | +34% |

These switching operations include parsing, preparing/copying the first output,
then preparing/copying the second. The old implementation cleaned cells during
parsing and reused them for both writers. Preserving source content moves that
work into each writer. Repeated cleanup is a likely contributor to the gap;
separating its cost from allocation and JavaScript dispatch needs profiling.
Restoring a shared prepared grid would conflict with the chosen memory policy.
Shared cleanup knowledge would also need an explicit ownership and policy design.

A straightforward detection fix is included: reject non-Markdown input before
normalizing line endings. Otherwise large non-Markdown sources were copied only
to reject them. More involved optimization was deferred.

## Preview and first-copy latency

The `latency-*` records split a warmed conversion into preview time, additional
first-copy time, and their sum. These are individual observations rather than
batch medians. Representative JavaScript measurements, in ms:

| Fixture / output | Before preview / copy / total | After preview / copy / total |
| --- | ---: | ---: |
| Tall ASCII / Slack | 29 / 0 / 29 | 22 / 14 / 36 |
| Wide Unicode / Markdown | 201 / 0 / 201 | 27 / 180 / 207 |
| Whitespace / Markdown | 62 / 0 / 62 | 24 / 25 / 49 |
| Long cells / Slack | 36 / 0 / 36 | 23 / 6 / 29 |

The old frontend eagerly completed output before previewing; zero additional copy
time reflects that earlier work. The new first copy performs deferred work
synchronously. Preview speed alone does not establish the total-work target.

## Peak memory

Each measurement ran one fixture and operation in a fresh process under macOS
`/usr/bin/time -l`. Values include runtime startup and fixture generation, so they
are process high-water RSS rather than isolated retained-heap measurements. These
single-process samples show no substantial full-conversion memory increase;
small differences should not be treated as precise allocation measurements.

Representative peak RSS, in MiB:

| Runtime / fixture / destination | Before preview | After preview | Before preview + full | After preview + full |
| --- | ---: | ---: | ---: | ---: |
| Native / tall ASCII / Slack | 83.4 | 67.3 | 77.7 | 77.5 |
| Native / long cells / Markdown | 74.2 | 55.5 | 74.1 | 73.7 |
| JavaScript / wide Unicode / Markdown | 220.1 | 146.1 | 220.7 | 210.5 |
| JavaScript / long cells / Slack | 114.2 | 90.2 | 113.5 | 107.0 |

The cache remains bounded by the requested rectangle, not a byte budget. Large
individual cells can still dominate preview work and retained prepared text.

## Reproduction

Compile the same lifecycle harness against each revision's package configuration
(copy the harness into the baseline checkout when measuring an older revision).
From the web package:

```sh
dart compile exe tool/benchmark_pipeline.dart -o ../../build/benchmark_pipeline
../../build/benchmark_pipeline
dart compile js -O2 --no-source-maps tool/benchmark_pipeline.dart -o ../../build/benchmark_pipeline.js
node tool/run_dart_js.cjs ../../build/benchmark_pipeline.js
```

Append fixture filters and an operation to repeat a focused comparison:

```sh
node tool/run_dart_js.cjs ../../build/benchmark_pipeline.js --mode=switch-slack tall-ascii long-cells
/usr/bin/time -l ../../build/benchmark_pipeline --once --mode=preview-full-slack long-cells
```

The ordinary core benchmark was also compared in optimized native and JavaScript
builds before migration. Deterministic tests cover preservation, prepared
previews, character budgets, rectangle reuse/eviction, full-first access,
full-output caching, and conversion-scoped scan reuse. Timing assertions are not
part of those tests.
