#!/usr/bin/env bash
# Generates a GitHub issue dependency graph using your gh login (no manual token).
#
# Usage:
#   ./issue-graph.sh owner/repo            # open issues only
#   ./issue-graph.sh owner/repo --all      # include closed issues
#   ./issue-graph.sh owner/repo -o file.html --no-open
#
# Requires: gh (logged in: gh auth login) and issue-graph.html next to this script.
set -euo pipefail

usage(){ sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

REPO=""; ALL=0; OUT=""; OPEN_AFTER=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --all) ALL=1 ;;
    -o|--out) OUT="${2:-}"; shift ;;
    --no-open) OPEN_AFTER=0 ;;
    -h|--help) usage ;;
    */*) REPO="$1" ;;
    *) echo "Unknown argument: $1" >&2; usage ;;
  esac
  shift
done
[[ -n "$REPO" ]] || usage
REPO="${REPO#https://github.com/}"; REPO="${REPO%/}"
OWNER="${REPO%%/*}"; NAME="${REPO#*/}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/issue-graph.html"
[[ -f "$TEMPLATE" ]] || { echo "Template not found: $TEMPLATE" >&2; exit 1; }
command -v gh >/dev/null || { echo "gh not found. Install it: https://cli.github.com" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "gh is not logged in. Run: gh auth login" >&2; exit 1; }

[[ -n "$OUT" ]] || OUT="issue-graph-${OWNER}_${NAME}.html"
if [[ $ALL -eq 1 ]]; then STATES=""; OPEN_JSON=false; else STATES="states:[OPEN],"; OPEN_JSON=true; fi

QUERY="query(\$owner:String!,\$name:String!,\$endCursor:String){
  repository(owner:\$owner,name:\$name){
    issues(first:100,after:\$endCursor,${STATES}orderBy:{field:CREATED_AT,direction:ASC}){
      pageInfo{hasNextPage endCursor}
      nodes{
        number title state url body
        assignees(first:2){nodes{login}}
        blockedBy(first:50){nodes{number title state url repository{nameWithOwner}}}
      }
    }
  }
}"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
echo "Fetching issues from $REPO via gh…" >&2
if ! gh api graphql --paginate --slurp -f query="$QUERY" -F owner="$OWNER" -F name="$NAME" > "$TMP/pages.json" 2> "$TMP/err.txt"; then
  cat "$TMP/err.txt" >&2
  if grep -qiE 'saml|sso' "$TMP/err.txt"; then
    echo "→ The organization requires SSO. Try: gh auth refresh -h github.com, then authorize SSO in the browser." >&2
  fi
  exit 1
fi
if grep -q '"repository":null' "$TMP/pages.json"; then
  echo "Repository $REPO not found, or your gh account has no access to it." >&2; exit 1
fi

# Embed data into a copy of the template ("</" escaped so issue text cannot close the <script> tag)
{
  printf '{"repo":"%s","generatedAt":"%s","openOnly":%s,"pages":' "$REPO" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$OPEN_JSON"
  sed 's#</#<\\/#g' "$TMP/pages.json"
  printf '}'
} > "$TMP/data.json"

MARKER='<script type="application/json" id="embedded">null</script>'
grep -qF "$MARKER" "$TEMPLATE" || { echo "Template has no data marker — use the current issue-graph.html." >&2; exit 1; }
awk -v marker="$MARKER" -v data="$TMP/data.json" '
  $0 == marker {
    print "<script type=\"application/json\" id=\"embedded\">"
    while ((getline line < data) > 0) print line
    print "</script>"
    next
  }
  { print }
' "$TEMPLATE" > "$OUT"

echo "Saved: $OUT" >&2

if [[ $OPEN_AFTER -eq 1 ]]; then
  if command -v open >/dev/null; then open "$OUT"
  elif command -v xdg-open >/dev/null; then xdg-open "$OUT" >/dev/null 2>&1 &
  elif command -v start >/dev/null; then start "" "$OUT"
  fi
fi
