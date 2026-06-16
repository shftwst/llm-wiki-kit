#!/usr/bin/env bash
# ingest-new.sh — detect new/changed sources and ingest them via headless Claude Code.
#
#   ./scripts/ingest-new.sh            supervised: scan, then ingest pending
#   ./scripts/ingest-new.sh --dry-run  detect only; print what would run (no LLM, no cost)
#   ./scripts/ingest-new.sh --auto     unattended permissions (for cron / launchd)
#
# Set CLAUDE_BIN=/path/to/claude if 'claude' is not on PATH.

set -euo pipefail

KB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCAN="$KB_DIR/scripts/scan.sh"

DRY_RUN=0; AUTO=0
for a in "${@:-}"; do
  case "$a" in
    "") ;;
    --dry-run) DRY_RUN=1;;
    --auto)    AUTO=1;;
    *) echo "ingest-new: unknown arg: $a" >&2; exit 1;;
  esac
done

CLAUDE_BIN="${CLAUDE_BIN:-claude}"
if [ "$AUTO" -eq 1 ]; then
  PERM=(--permission-mode bypassPermissions)   # unattended: no prompts
else
  PERM=(--permission-mode acceptEdits)         # supervised: auto-accept edits
fi

PROMPT='Mechanical ingest run. Read .ingest/pending.md and follow this KB'"'"'s CLAUDE.md.
For every source under New and Changed, run the Ingest or Re-ingest workflow; for Removed,
reconcile the affected wiki pages. This is an UNATTENDED ingest: skip the discussion step,
mark anything uncertain or contradictory with a "> [!review]" callout on the page, and
summarize what you did plus every [!review] you raised in the log.md entry. Do NOT edit
.ingest/manifest.tsv and do NOT git commit — the wrapper advances the manifest and commits.'

# --- detect ------------------------------------------------------------------
set +e; bash "$SCAN"; code=$?; set -e
case "$code" in
  0)  echo "ingest-new: nothing pending — done."; exit 0;;
  10) ;;  # pending work exists
  *)  echo "ingest-new: scan failed (exit $code)" >&2; exit "$code";;
esac

if [ "$DRY_RUN" -eq 1 ]; then
  echo "ingest-new: [dry-run] changes pending. Would run, in $KB_DIR:"
  echo "  $CLAUDE_BIN -p ${PERM[*]} \"<unattended ingest prompt>\""
  echo "  then: scripts/scan.sh --accept && git add -A && git commit"
  echo "ingest-new: [dry-run] no changes made."
  exit 0
fi

command -v "$CLAUDE_BIN" >/dev/null 2>&1 \
  || { echo "ingest-new: '$CLAUDE_BIN' not found. Set CLAUDE_BIN=/path/to/claude." >&2; exit 127; }

echo "ingest-new: ingesting pending sources via $CLAUDE_BIN ..."
( cd "$KB_DIR" && "$CLAUDE_BIN" -p "${PERM[@]}" "$PROMPT" )

echo "ingest-new: advancing manifest baseline + committing ..."
"$SCAN" --accept >/dev/null
( cd "$KB_DIR" && git add -A && git commit -q -m "Mechanical ingest ($(date +%F))" ) \
  || echo "ingest-new: nothing to commit."
echo "ingest-new: done."
