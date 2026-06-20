#!/usr/bin/env bash
# content.test.sh — builds a tiny fixture KB in a temp dir and checks scripts/content output.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1" >&2; exit 1; }

# Fixture KB: schema + scripts + two content pages and one nav page.
mkdir -p "$TMP/.schema" "$TMP/scripts" "$TMP/wiki/concepts"
cp "$HERE/kblib.sh" "$TMP/scripts/kblib.sh"
cp "$HERE/content" "$TMP/scripts/content"
printf 'source\tsource\tsources\t-\nconcept\tcontent\tconcepts\t-\noverview\tnav\t.\t-\n' > "$TMP/.schema/page-types.tsv"
printf 'default\t0\t-\t-\nbusiness-sensitive\t1\tbusiness\t-\n' > "$TMP/.schema/privilege-tiers.tsv"
printf -- '---\ntype: concept\nprivilege: business-sensitive\nupdated: 2026-06-19\n---\n\n# Banking\n\nAccounts text.\n' > "$TMP/wiki/concepts/banking.md"
printf -- '---\ntype: concept\nupdated: 2026-06-01\n---\n\n# Expenses\n\nExpenses text.\n' > "$TMP/wiki/concepts/expenses.md"
printf -- '---\ntype: overview\n---\n\n# Home\n\nNav page.\n' > "$TMP/wiki/overview.md"

man="$("$TMP/scripts/content" --manifest)"
echo "$man" | jq -e 'select(.id=="concepts/banking") | .hash | length > 0' >/dev/null || fail "manifest missing banking hash"
echo "$man" | grep -q '"overview"' && fail "manifest included nav page"
[ "$(echo "$man" | wc -l | tr -d ' ')" = "2" ] || fail "manifest should list exactly 2 content pages"

rec="$(printf 'concepts/banking\nconcepts/expenses\n' | "$TMP/scripts/content" --get)"
echo "$rec" | jq -e 'select(.id=="concepts/banking") | .frontmatter.privilege=="business-sensitive" and .title=="Banking" and (.body|test("Accounts text"))' >/dev/null || fail "banking record wrong"
echo "$rec" | jq -e 'select(.id=="concepts/expenses") | .frontmatter.privilege=="default"' >/dev/null || fail "missing-privilege page should default to lowest tier"

echo "PASS"
