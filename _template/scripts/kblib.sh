# kblib.sh — shared readers for this KB's schema config in .schema/ (page-types.tsv,
# privilege-tiers.tsv). Sourced by lint, classify, and publish; the caller must set KB_DIR
# first. Both files are required (the kit scaffolds them) — a missing one is a hard error, not
# a silent default, so a broken setup fails loudly.
#
# No bash 4 features (associative arrays): everything is awk/cut over the TSVs, bash 3.2 safe.

_KB_TYPES_TSV="$KB_DIR/.schema/page-types.tsv"
_KB_TIERS_TSV="$KB_DIR/.schema/privilege-tiers.tsv"
[ -f "$_KB_TYPES_TSV" ] || { echo "kblib: missing $_KB_TYPES_TSV" >&2; exit 1; }
[ -f "$_KB_TIERS_TSV" ] || { echo "kblib: missing $_KB_TIERS_TSV" >&2; exit 1; }

_kb_types_raw() { grep -v '^#' "$_KB_TYPES_TSV" | grep -vE '^[[:space:]]*$' || true; }
_kb_tiers_raw() { grep -v '^#' "$_KB_TIERS_TSV" | grep -vE '^[[:space:]]*$' || true; }

# Page types -----------------------------------------------------------------
kb_types()        { _kb_types_raw | cut -f1; }
kb_type_valid()   { _kb_types_raw | cut -f1 | grep -qxF "$1"; }                      # exit 0 if $1 is a known type
kb_type_class()   { _kb_types_raw | awk -F'\t' -v t="$1" '$1==t{print $2; exit}'; }  # content|source|nav|""

# Privilege tiers ------------------------------------------------------------
kb_tiers()        { _kb_tiers_raw | awk -F'\t' '{print $2"\t"$1}' | sort -n | cut -f2; }  # names, rank order
kb_tier_valid()   { _kb_tiers_raw | cut -f1 | grep -qxF "$1"; }                            # exit 0 if $1 is a known tier
kb_top_tier()     { _kb_tiers_raw | awk -F'\t' '{print $2"\t"$1}' | sort -n | tail -1 | cut -f2; }
# Tier carrying a given classify bucket (business|personal); falls back to the most sensitive.
kb_tier_for_bucket() { t="$(_kb_tiers_raw | awk -F'\t' -v b="$1" '$3==b{print $1; exit}')"; [ -n "$t" ] && printf '%s' "$t" || kb_top_tier; }
