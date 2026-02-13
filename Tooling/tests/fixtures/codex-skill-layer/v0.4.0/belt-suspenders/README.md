# Belt-and-Suspenders Orchestration Playbook

Local-first / remote-confirmation operator playbook.

## High-Level Flow
1. Run local proactive loop to satisfy selected success target.
2. Dispatch `CI Pipeline (Composite)` for exact SHA.
3. Wait for completion.
4. If non-success, run CI-debt analysis and attach diagnostics.

Runtime scripts remain repo-local in this phase.
