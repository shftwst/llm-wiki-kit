# Learning from use, Phase 2b (query-driven depth) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When the wiki can't answer but the data is in an unread source, flag that source (log it to `.ingest/demand.tsv`), read it first on the next ingest, and show the backlog in `stats`. No paid read on the query path.

**Architecture:** A query-miss appends `date⇥source⇥note` to a new append-only `demand.tsv` sidecar (the agent never reads inline or writes `coverage.tsv`). The ingest read/deepen `POLICY` reads demanded sources first. `stats` aggregates `demand.tsv` joined to `coverage.tsv` status. The inline "read it now" read is deferred; `demand.tsv` is its foundation.

**Tech Stack:** Bash (`_template/scripts/`), two-file `awk` join, headless Claude Code for the agent behaviours. No test framework; deterministic pieces checked with shell assertions against a scratch KB, agent behaviour by a human smoke run.

## Global Constraints

- `.ingest/demand.tsv` is append-only, columns `date⇥source⇥note`: `source` = a `coverage.tsv` path, `note` = a short topic phrase, **never the verbatim question**.
- A query-miss **does not** read inline and **does not** write `coverage.tsv` (Phase 1 guard); it only appends to the `demand.tsv` sidecar. All reading stays on the ingest path.
- The ingest read/deepen pass reads still-`unread`/`partial` demanded sources **first**, ahead of the value/freshness order; once read they leave the backlog naturally (no explicit cleanup).
- `stats` edits keep `set -eu` (no pipefail) and the existing `have()`/`awk` idioms.
- All prose obeys `STYLE.md` (no banned vocab, straight quotes, em-dashes sparse, sentence-case headings). The literal `demand.tsv` header and `stats` "(none yet — …)" em-dashes match the kit's `cost.tsv`/`stats` convention and are kept.
- Edits target `_template/`. The generated `1-knowledge-layer/shftwst-ops-kb` is synced only in Task 5 (scripts wholesale; `AGENTS.md` by targeted edit only, never `cp`).
- Spec: `docs/learning-phase2b.md`. Rationale: `docs/learning.md` §7.

---

### Task 1: `scripts/stats` DEMANDED + ship the `demand.tsv` ledger

**Files:**
- Create: `_template/.ingest/demand.tsv`
- Modify: `_template/scripts/stats` (var decls ~12-21; new section after the MOST QUERIED block, before the `# --- cost` block at ~146)
- Test bed: a scratch KB at `../wiki-gen-smoke`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: a `DEMANDED (.ingest/demand.tsv)` section that joins `demand.tsv` counts to `coverage.tsv` status; the template ledger every KB ships. Later tasks (the agent logging in Task 2) write rows this reads.

- [ ] **Step 1: Write the failing test**

```bash
# from the kit root (parent of _template/)
setup_smoke() {
  [ -d ../wiki-gen-smoke ] || ./scripts/new-kb wiki-gen-smoke "Smoke" >/dev/null 2>&1
}
test_stats_demand() {
  setup_smoke
  cp _template/scripts/stats ../wiki-gen-smoke/scripts/stats
  # coverage fixture: one unread, one read (7 TAB columns)
  printf '# coverage\n# path\tvalue\tstatus\tpass\tlast_read\tfingerprint\tnotes\nFinance/Tax/YE2025/T5\thigh\tunread\t0\t-\t-\t\nInsurance/2024/policy.pdf\tmed\tread\t1\t2026-06-01\tabc\t\n' > ../wiki-gen-smoke/.ingest/coverage.tsv
  # demand fixture: T5 twice, insurance once
  printf '# demand\n# Columns: date\tsource\tnote\n2026-06-10\tFinance/Tax/YE2025/T5\t2024 T5 dividend total\n2026-06-12\tFinance/Tax/YE2025/T5\tT5 slip amount\n2026-06-15\tInsurance/2024/policy.pdf\tcyber coverage limit\n' > ../wiki-gen-smoke/.ingest/demand.tsv
  out="$(../wiki-gen-smoke/scripts/stats 2>&1 || true)"
  echo "$out" | grep -qE 'logged +3 demand\(s\) across 2 source\(s\)' || { echo "FAIL: totals wrong"; echo "$out" | grep -i demand; return 1; }
  echo "$out" | grep -qE '2 +Finance/Tax/YE2025/T5 +\[unread\] +\(last asked 2026-06-12\)' || { echo "FAIL: top row wrong"; echo "$out" | grep -i T5; return 1; }
  # empty (header-only) demand -> (none yet ...)
  printf '# demand\n# Columns: date\tsource\tnote\n' > ../wiki-gen-smoke/.ingest/demand.tsv
  out="$(../wiki-gen-smoke/scripts/stats 2>&1 || true)"
  echo "$out" | grep -q 'none yet' || { echo "FAIL: empty case missing"; return 1; }
  echo PASS
}
test_stats_demand
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash -c "$(declare -f setup_smoke test_stats_demand); test_stats_demand"`
Expected: `FAIL: totals wrong` (no DEMANDED section yet).

- [ ] **Step 3: Create the template ledger**

Create `_template/.ingest/demand.tsv` with exactly two header lines (a real TAB on the Columns line, no data rows):

```
# demand.tsv — sources a query needed but had not read yet (appended by the agent on a miss).
# Columns: date	source	note   (source = coverage.tsv path; note = short topic only, no question text)
```

- [ ] **Step 4: Add the `DEMAND` var and the DEMANDED section to `stats`**

In `_template/scripts/stats`, after the `COST="$KB_DIR/.ingest/cost.tsv"` line, add:

```bash
DEMAND="$KB_DIR/.ingest/demand.tsv"
```

Then insert this block immediately after the MOST QUERIED block (the `fi` that closes it) and before the `# --- cost` comment block:

```bash
# --- demand (query-driven depth signal) -------------------------------------
printf '\nDEMANDED (.ingest/demand.tsv)\n'; rule
if have "$DEMAND"; then
  covf="$COVERAGE"; [ -f "$covf" ] || covf=/dev/null
  awk -F'\t' '
    FNR==NR { if($1!~/^#/ && $1!="") cov[$1]=$3; next }
    $1~/^#/ || $1=="" {next}
    { n++; c[$2]++ }
    END{ ns=0; for(s in c) ns++; printf "  logged         %d demand(s) across %d source(s)\n", n, ns }
  ' "$covf" "$DEMAND"
  printf '  most demanded:\n'
  awk -F'\t' '
    FNR==NR { if($1!~/^#/ && $1!="") cov[$1]=$3; next }
    $1~/^#/ || $1=="" {next}
    { c[$2]++; if($1>last[$2]) last[$2]=$1 }
    END{ for(s in c){ st=(s in cov)?cov[s]:"?"; printf "%d\t%s\t%s\t%s\n", c[s], s, st, last[s] } }
  ' "$covf" "$DEMAND" \
    | sort -rn | head -10 \
    | awk -F'\t' '{printf "    %4d  %-28s [%s]  (last asked %s)\n", $1, $2, $3, $4}'
else
  printf '  (none yet — a query logs a source here when its data is unread)\n'
fi

```

(The `covf=/dev/null` fallback means a missing `coverage.tsv` yields status `?` rather than an awk error under `set -eu`. ISO dates compare as strings. The `sort | head` pipeline is `set -e`-safe without pipefail.)

- [ ] **Step 5: Run the test to verify it passes**

Run: `cp _template/scripts/stats ../wiki-gen-smoke/scripts/stats && bash -c "$(declare -f setup_smoke test_stats_demand); test_stats_demand"`
Expected: `PASS`. Also `bash -n _template/scripts/stats`.

- [ ] **Step 6: Commit**

```bash
git add _template/scripts/stats _template/.ingest/demand.tsv
git commit -m "feat(stats): DEMANDED report; ship the demand.tsv ledger"
```

---

### Task 2: `AGENTS.md` — flag unread sources on a query miss

**Files:**
- Modify: `_template/AGENTS.md` (Query step 5, ~the `### Query` section)

**Interfaces:**
- Consumes: the `demand.tsv` ledger from Task 1.
- Produces: the agent behaviour that writes `demand.tsv` rows on a miss (Task 3's ingest clause reads them; Task 1's stats reports them).

- [ ] **Step 1: Replace Query step 5**

In `_template/AGENTS.md`, the `### Query` section's step 5 currently reads:

```markdown
5. If the wiki cannot answer, say so plainly and surface the gap. Do not read an unread source
   to close it; do not guess.
```

Replace it with:

```markdown
5. If the wiki cannot answer, read `.ingest/coverage.tsv`. If a plausibly relevant source is
   `unread` or `partial`, append a `date<TAB>source<TAB>note` row to `.ingest/demand.tsv` (source =
   its coverage path; note = a short topic phrase of what was needed, never the question text), and
   tell the user the answer likely lives in that source, which is not read yet and is now flagged
   for the next read pass. If no source plausibly covers the question, say it is a genuine gap. Do
   not read the source now to answer (that is a later phase) and do not guess; log the need and
   move on. Do not edit `.ingest/coverage.tsv`.
```

- [ ] **Step 2: Verify no style regressions and the edit landed**

Run from `_template/`:
```bash
./scripts/lint 2>&1 | grep -E 'AGENTS\.md' || echo "no AGENTS.md style warnings — good"
grep -q 'append a `date<TAB>source<TAB>note` row to `.ingest/demand.tsv`' AGENTS.md && echo "edit landed"
```
Expected: `no AGENTS.md style warnings — good` and `edit landed`.

- [ ] **Step 3: Commit**

```bash
git add _template/AGENTS.md
git commit -m "feat(query): flag an unread source to demand.tsv when the wiki cannot answer"
```

---

### Task 3: wire demand into the scripts (`ingest` reads first, `query` reminder)

**Files:**
- Modify: `_template/scripts/ingest` (after the `POLICY` if/else, ~line 104)
- Modify: `_template/scripts/query` (the `PROMPT` string, after the `queries.tsv` clause)

**Interfaces:**
- Consumes: `demand.tsv` (Task 1) and the Query workflow (Task 2).
- Produces: ingest reads demanded-but-unread sources first; the headless query prompt reinforces demand logging.

- [ ] **Step 1: Add the demand-first clause to the ingest `POLICY`**

In `_template/scripts/ingest`, the `POLICY` is set in an `if [ "$FRESH" -eq 1 ]` block. Find:

```bash
never preempts unread high-value."
fi
COV_CLAUSE=
```

Replace with:

```bash
never preempts unread high-value."
fi
POLICY="$POLICY Before that ordering, read .ingest/demand.tsv: any source listed there that is still unread or partial in coverage.tsv is read FIRST this pass, ahead of the value and freshness order, because a question needed it. Once read it leaves the demand backlog naturally (it is no longer unread)."
COV_CLAUSE=
```

(`POLICY` is interpolated only into the read and deepen prompts, so map and verify are unaffected.)

- [ ] **Step 2: Add the demand reminder to the query `PROMPT`**

In `_template/scripts/query`, the `PROMPT` string contains (from Phase 2a):

```
queries.tsv per the Query workflow (page slugs and a date only).
```

Replace that with:

```
queries.tsv per the Query workflow (page slugs and a date only). If you cannot answer and a relevant source is unread, log it to .ingest/demand.tsv per the Query workflow (source path and a short topic note only).
```

- [ ] **Step 3: Verify both edits landed and scripts parse**

Run from `_template/`:
```bash
grep -q 'read .ingest/demand.tsv: any source listed there' scripts/ingest && echo "ingest clause present"
grep -q 'log it to .ingest/demand.tsv per the Query workflow' scripts/query && echo "query clause present"
bash -n scripts/ingest && bash -n scripts/query && echo "syntax ok"
./scripts/ingest --deepen --dry-run 2>&1 | grep -q 'dry-run' && echo "ingest dry-run ok"
./scripts/query --dry-run "smoke" | grep -q 'dry-run' && echo "query dry-run ok"
```
Expected: all five lines print.

- [ ] **Step 4: Commit**

```bash
git add _template/scripts/ingest _template/scripts/query
git commit -m "feat(depth): ingest reads demanded sources first; query prompt logs demand"
```

---

### Task 4: Documentation

**Files:**
- Modify: `_template/scripts/README.md` (the `stats` section)
- Modify: `docs/learning.md` (top status header + §10 Phase 2b line)

**Interfaces:**
- Consumes: the finished behaviour.
- Produces: operator docs; no code.

- [ ] **Step 1: Note DEMANDED in the `stats` operator section**

In `_template/scripts/README.md`, the `## \`stats\`: ingestion summary` section. Append one sentence to its prose:

```markdown
It also reports **DEMANDED** sources from `.ingest/demand.tsv` (documents a query needed but had
not read yet, shown with their current coverage status), so you can see what to ingest next; the
read/deepen passes read demanded-but-unread sources first. See `../docs/learning.md` §7.
```

- [ ] **Step 2: Update the §10 Phase 2b line in `docs/learning.md`**

Replace:

```markdown
- **Phase 2b (query-driven depth).** Query-miss detection against `coverage.tsv` with an opt-in
  targeted read to answer now and a promotion for the next batch. Not built.
```

with:

```markdown
- **Phase 2b (query-driven depth). Promote built.** Query-miss detection against `coverage.tsv`: a
  relevant unread source is logged to `.ingest/demand.tsv`, read first on the next ingest pass, and
  shown in `stats`. See `learning-phase2b.md`. The opt-in inline read (answer now) is deferred.
```

- [ ] **Step 3: Update the top status header in `docs/learning.md`**

Replace:

```markdown
**Status: Phase 1 (file-back) and Phase 2a (prominence) are built; query-driven depth (Phase 2b)
and smarter dedup (Phase 3) are design only.** This records the architecture so the decisions are
```

with:

```markdown
**Status: Phase 1 (file-back), Phase 2a (prominence), and Phase 2b promote (query-driven depth
flagging) are built; the Phase 2b inline read and smarter dedup (Phase 3) are design only.** This
records the architecture so the decisions are
```

- [ ] **Step 4: Verify docs style and commit**

Run from `_template/`: `./scripts/lint 2>&1 | grep -E 'scripts/README' || echo "no scripts/README style warnings"` (expect the echo). Check `docs/learning.md` introduced no em-dash: `grep -c "—" ../docs/learning.md` should be unchanged from before.

```bash
git add _template/scripts/README.md docs/learning.md
git commit -m "docs(depth): document DEMANDED; mark Phase 2b promote built"
```

---

### Task 5: Smoke-test prep on `shftwst-ops-kb` and hand off

**Files:**
- Modify (sync wholesale): `1-knowledge-layer/shftwst-ops-kb/scripts/{stats,ingest,query}`, and `1-knowledge-layer/shftwst-ops-kb/.ingest/demand.tsv` (create if absent)
- Modify (targeted edit only, never `cp`): `1-knowledge-layer/shftwst-ops-kb/AGENTS.md` (apply the Task 2 step-5 replacement)

**Interfaces:**
- Consumes: every prior task.
- Produces: a live, human-watched acceptance run. The agent prepares; the human runs and judges.

- [ ] **Step 1: Sync the scripts and ledger**

Work from `/Users/shftwst/workspace/shftwst/pinky`:
```bash
cp llm-wiki-gen/_template/scripts/stats llm-wiki-gen/_template/scripts/ingest llm-wiki-gen/_template/scripts/query \
   1-knowledge-layer/shftwst-ops-kb/scripts/
[ -f 1-knowledge-layer/shftwst-ops-kb/.ingest/demand.tsv ] \
  || cp llm-wiki-gen/_template/.ingest/demand.tsv 1-knowledge-layer/shftwst-ops-kb/.ingest/demand.tsv
```

- [ ] **Step 2: Apply ONLY the Query step-5 edit to the ops KB `AGENTS.md`**

Apply the same step-5 replacement from Task 2 to `1-knowledge-layer/shftwst-ops-kb/AGENTS.md` with a targeted Edit (the step-5 anchor matches). **Do not `cp` the template `AGENTS.md` over it — it carries the real shiftwest charter.** Verify:
```bash
grep -q 'append a `date<TAB>source<TAB>note` row to `.ingest/demand.tsv`' 1-knowledge-layer/shftwst-ops-kb/AGENTS.md && echo "ops KB updated"
grep -c '{{' 1-knowledge-layer/shftwst-ops-kb/AGENTS.md   # expect 0 (charter intact)
```

- [ ] **Step 3: Deterministic pre-check in the ops KB**

```bash
cd 1-knowledge-layer/shftwst-ops-kb
./scripts/stats | grep -A4 'DEMANDED'        # the section ((none yet ...) until a miss is logged)
./scripts/query --dry-run "smoke"             # dry-run banner, no changes
./scripts/ingest --deepen --dry-run | grep -q dry-run && echo "ingest dry-run ok"
cd -
```
Expected: a DEMANDED section, the dry-run banner, `ingest dry-run ok`.

- [ ] **Step 4: Hand off the live run to the human (acceptance)**

Run by the user (paid LLM calls):

```bash
cd 1-knowledge-layer/shftwst-ops-kb
# ask something whose source is unread (the 2024 T5 slip is flagged [!review] as unread)
./scripts/query "what was the exact 2024 T5 dividend total on the slip?"
# expect: the agent says it's not read yet / flagged, and appends a row:
cat .ingest/demand.tsv
./scripts/stats | grep -A6 'DEMANDED'        # the source listed as [unread]
# next deepen should read the demanded source FIRST (watch the stream for it)
./scripts/ingest --deepen --watch
./scripts/stats | grep -A6 'DEMANDED'        # the source now [read] (drops off the live backlog)
```

Acceptance: a miss appends a `demand.tsv` row (source path + short note, **no question text**); `stats` DEMANDED lists it `[unread]`; the next deepen reads it first; afterwards it shows `[read]`. Failure modes: question text in `demand.tsv`, or the query reading inline / writing `coverage.tsv` — both are `AGENTS.md` wording fixes, no script change.

- [ ] **Step 5: Commit the ops-KB sync (after the human is satisfied)**

```bash
cd 1-knowledge-layer/shftwst-ops-kb
git add -A && git commit -m "chore: adopt Phase 2b query-driven depth (scripts + AGENTS.md + demand.tsv)"
cd -
```

---

## Cleanup

After acceptance, remove the scratch KB: `rm -rf ../wiki-gen-smoke`.

## Notes for the implementer

- The miss detection, demand logging, and reading-demanded-first are LLM behaviours in `AGENTS.md` and the ingest prompt; their only real test is the Task 5 smoke run. The shell checks in Tasks 2-3 confirm the edits are present and the scripts parse.
- Keep the `stats` DEMANDED block read-only and `set -eu`-safe; match the existing MOST QUERIED / RELEVANCE idioms.
