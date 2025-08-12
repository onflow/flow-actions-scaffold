# AI Documentation Maintenance Guide (Do not include in agent context)

Audience: AI agents acting as documentation maintainers when instructed by humans. This is a meta-guide for updating the documentation files that the next AI agent will use. This file should not be included in runtime agent prompts.

> Keep all links relative (e.g., `./docs/...`) so they remain valid when pages are copied to other contexts.

## Persona: Next‑gen DeFiActions Agent (consumer of these rules)
- Who it is: A code‑generation agent (Cursor) that composes Cadence transactions using DeFiActions connectors.
- Context budget: Small-to-medium window. Prefers a single, canonical entry doc with minimal duplication.
- Entrypoint: [`defi-actions/ai-generation-entrypoint.mdc`](./defi-actions/ai-generation-entrypoint.mdc) (explicitly labeled ENTRYPOINT). Follows cross‑links only as needed.
- Operating assumptions:
  - String imports only; no addresses in source.
  - Chain: `PoolRewardsSource -> SwapSource(Zapper) -> PoolSink` for restake.
  - Minimal parameters: restake takes only `pid`. Derive pair token types and `stableMode` from the pool pair.
  - Size ops by `source.minimumAvailable()` and `sink.minimumCapacity()`; no manual slippage math.
  - Pre/Post: single boolean expression; compute `expectedStakeIncrease` for restake and assert against it.
  - Resource safety: assert `vault.balance == 0.0` before `destroy`.
- Style expectations: Named args, readable identifiers, short intent comments at block starts and before key steps.
- What it will NOT read at runtime: This maintainer file. It reads the ENTRYPOINT and linked docs only.

## Goals
- Keep docs concise for small context windows, but accurate to current contracts.
- Reduce redundancy: Prefer canonical pages and cross-linking.
- Capture non-obvious nuances briefly (e.g., Zapper quoteOut usage, sink-driven sizing, token ordering reversal).

## Cross-file Linking
- Always use relative markdown links (never bare paths or absolute links). Examples:
  - Correct: [`defi-actions/index.md`](./defi-actions/index.md)
  - Correct: [workflows/restaking-workflow.md](./defi-actions/workflows/restaking-workflow.md)
- [`defi-actions/index.md`](./defi-actions/index.md): links to all key pages and marks [`ai-generation-entrypoint.mdc`](./defi-actions/ai-generation-entrypoint.mdc) as ENTRYPOINT.
- Each guidance page ends with cross-links to related pages (agent rules → connectors/composition/checklist/workflows).
- Workflows reference connectors and templates by anchors.

## Style Decisions
- Transaction block order is `prepare` → `pre` → `post` → `execute` (readability/auditability).
- When immediately depositing into a sink, size `withdrawAvailable(maxAmount:)` by `sink.minimumCapacity()`.
- Use string imports exactly; no address literals in docs.
- Prefer helpers over raw addresses (e.g., `borrowPool(pid:)`).
- Restake documentation: single canonical workflow in [`workflows/restaking-workflow.md`](./defi-actions/workflows/restaking-workflow.md); templates page references it instead of duplicating.

## Success Criteria for the next AI agent’s outputs (guardrails)
- Restake transactions accept only `pid`; do not introduce `rewardTokenType`, `pairTokenType`, or `minimumRestakedAmount`.
- Derive pair token types and `stableMode` via `borrowPairPublicByPid(pid)` and `tokenTypeIdentifierToVaultType(_:)`. Check if `rewardsSource.getSourceType() != token0Type` and reverse token order if true (reward token should be token0, the input).
- Compute `expectedStakeIncrease = zapper.quoteOut(forProvided: rewards.minimumAvailable(), reverse: false).outAmount` and assert `newStake >= startingStake + expectedStakeIncrease` in `post`.
- Use `withdrawAvailable(maxAmount: sink.minimumCapacity())` when immediately depositing.
- Verify complete transfers with `assert(vault.balance == 0.0)` before `destroy`.

## Anti‑patterns to catch and remove during edits
- Adding params for restake beyond `pid` (e.g., `rewardTokenType`, `pairTokenType`, `minimumRestakedAmount`).
- Hardcoded addresses or contract paths; non‑string imports.
- Manual slippage math for restake; not using source/sink capacities.
- Multi‑statement `pre`/`post` blocks.
- Destroying a non‑empty vault (missing residual check).

## Nuances surfaced from code/tests
- IncrementFi Zapper:
  - `quoteIn` is placeholder (supports `UFix64.max` only). Prefer `quoteOut` and capacity‑driven sizing.
  - `swapBack` returns token0 (swapper `inType`).
  - **Token Ordering**: When using with a source, check if `source.getSourceType() != token0Type` and reverse token order if true (reward token should be token0, the input). Zapper takes token0 as input and pairs it with token1 to create token0:token1 LP tokens.
- `SwapConnectors.SwapSink` computes input using `quoteIn(forDesired: sink.minimumCapacity())` internally.

## Open Candidates for Future Iteration
- Core Framework: add a one‑liner under Source/Sink explaining sink‑driven sizing when chaining.
- Testing page: add a brief example asserting `vault.balance == 0.0` after deposit in more scenarios.
- Consider a compact “Events and IDs” note: `createUniqueIdentifier`, `alignID` usage patterns for tracing (only if needed).

## Editor Checklist for Future PRs
- When changing connector signatures, update: [`connectors.md`](./defi-actions/connectors.md), examples in [`composition.md`](./defi-actions/composition.md), templates, [`ai-generation-guide.md`](./defi-actions/ai-generation-guide.md), [`ai-generation-entrypoint.mdc`](./defi-actions/ai-generation-entrypoint.mdc), and any workflow pages.
- Search/replace for outdated module names (`SwapStack`, `FungibleTokenStack`) and for `poolID:` labels.
- Verify all `withdrawAvailable(maxAmount:)` calls that immediately deposit into a sink use `sink.minimumCapacity()`.
- Keep [`ai-generation-entrypoint.mdc`](./defi-actions/ai-generation-entrypoint.mdc) minimal and paste‑ready for `.cursor/rules`. 

## Not in Agent Context
- This file is meta‑documentation for AI agents acting as maintainers. Do not feed into runtime AI prompts for the next generation AI agent. 