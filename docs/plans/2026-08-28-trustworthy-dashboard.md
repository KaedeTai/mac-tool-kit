# Trustworthy Dashboard implementation plan

Date: 2026-08-28

## Approved constraints

- User: “請完整修復，然後讓這個 Dashboard 變成一個可以信任的 Dashboard。可以照你建議的做。”
- User update: eliminate the generic “狀態不明” presentation. Use exact Codex local turn state when available, then classify other providers from matching Mac processes, project CWD, and recent provider-log activity as Active, Idle, or Inactive with the derivation shown.
- User: inactive sessions may remain in Recent for 24 hours, then move to permanent History.
- Cost rule: remove actual-spend presentation entirely. Token-based multiplication is shown only as an API-equivalent standard-rate estimate and must never be described as subscription, credit, or invoice spend.

## Data contract

Every displayed field has one of these provenance classes:

1. `measured`: sampled from a macOS, Docker, helper, or provider interface.
2. `providerReported`: copied from a provider log or billing response.
3. `derived`: calculated from measured inputs with the formula named in the UI.
4. `estimated`: a clearly optional comparison that is excluded from factual totals.
5. `unavailable`: the source does not expose a trustworthy value.

Active state uses an exact provider task state when available. Otherwise it requires both a matching provider process/project CWD and provider-log activity within the configured 30-second window. A matching process without recent activity is Idle; no matching process is Inactive. The UI shows the evidence source for every decision.

## Call-site and compatibility map

| Shared contract | Production consumers | Test consumers | Migration rule |
|---|---|---|---|
| `AISessionRecord` | three provider parsers, analytics engine, AI view | AI analytics tests | Add parent ID, provenance, optional cost and transcript span; retain compatibility defaults during migration |
| `AIProjectWorkspace` | analytics engine, AI view | AI analytics tests | Replace flat child bucket with children keyed to their exact main session and an explicit Unlinked bucket |
| `AISessionStatus` | parsers, runtime reconciler, AI status UI | lifecycle/runtime tests | Reconcile into Active, Idle, Inactive, or Aborted; keep legacy Unknown only for persisted decoding compatibility |
| `CodexRuntimeStatusProbe` | analytics engine | SQLite fixture tests | Read the latest exact turn status from `~/.codex/thread_history_1.sqlite` in read-only mode |
| `HIDTemperatureReducer` | hardware sensor monitor, Fan tab | named-family reducer tests | Accept PMU tdie*, NAND CH* temp, and gas-gauge battery only; never relabel SMC prefixes as CPU/GPU/RAM |
| CPU core type | CPU monitor and CPU view | metrics tests | Use `sysctl hw.perflevel*` labels; do not infer P/E from core index |
| fan readback | helper client, fan VM, overview and thermal view | fan tests | Keep actual and target distinct; zero actual remains zero/unavailable |
| process command | process monitor and process UI | redaction tests | Store/display a redacted command only |

## Implementation sequence

1. Add failing fixture-based tests for factual Codex token/cwd/title parsing, Claude parent-child relationships, lifecycle classification, optional cost, network 64-bit counters, CPU topology labels, fan partial writes, Lag severity, and command redaction.
2. Replace AI provider guesses with adapters that return normalized evidence. Parse all available source sessions, merge them into an Application Support history store, and preserve sessions after source rotation.
3. Build Project → Main session → Subagent presentation with Active, Recent, and History scopes. Show Unlinked children explicitly.
4. Remove fabricated telemetry from system tabs. Correct topology/counters/Docker fields, expose derivation labels, and show unavailable readings when no physical source exists.
5. Make remediation outcomes truthful: check command exit status, require both fan writes, exclude this Dashboard from termination advice, and never substitute target RPM for actual RPM.
6. Run package tests, coverage, build, hostile-input tests, static security checks, and shared-contract regression search.
7. Launch the native app, inspect and capture all eight tabs, compare the rendered state with source output, then update the progress tracker and design site.

## Verification commands

```sh
swift test --enable-code-coverage
swift build
swift test --show-codecov-path
rg -n "approx|estimate|hard.?cod|1800|gpt-4o|claude-3-7-sonnet|chmod\(.*0666|livePID != nil" Sources
git diff --check
```

Destructive UI actions (purge, process termination, Docker prune, and manual fan writes) are verified with injected command results and safe readback tests. They are not executed against unrelated live workloads merely to obtain a green screenshot.
