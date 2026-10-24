#!/usr/bin/env bash
# Generates a GitHub issue dependency graph using your gh login (no manual token).
#
# Usage:
#   ./issue-graph.sh owner/repo            # open issues only
#   ./issue-graph.sh owner/repo --all      # include closed issues
#   ./issue-graph.sh owner/repo -o file.html --no-open
#   ./issue-graph.sh https://github.example.com/owner/repo   # GitHub Enterprise Server
#   ./issue-graph.sh owner/repo --cdn      # small output file, Mermaid loaded from CDN
#
# Requires: gh (logged in: gh auth login) and issue-graph.html (or issue-graph-cdn.html for --cdn)
# next to this script.
set -euo pipefail

usage(){ sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

REPO=""; ALL=0; OUT=""; OPEN_AFTER=1; CDN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --all) ALL=1 ;;
    -o|--out) OUT="${2:-}"; shift ;;
    --no-open) OPEN_AFTER=0 ;;
    --cdn) CDN=1 ;;
    -h|--help) usage ;;
    */*) REPO="$1" ;;
    *) echo "Unknown argument: $1" >&2; usage ;;
  esac
  shift
done
[[ -n "$REPO" ]] || usage
# Accept owner/repo or a full URL, including GitHub Enterprise hosts
REPO="${REPO#http://}"; REPO="${REPO#https://}"; REPO="${REPO%%[?#]*}"; REPO="${REPO%.git}"; REPO="${REPO%/}"
HOST="github.com"
FIRST="${REPO%%/*}"
if [[ "$FIRST" == *.* ]]; then HOST="$FIRST"; REPO="${REPO#*/}"; fi
OWNER="$(cut -d/ -f1 <<<"$REPO")"; NAME="$(cut -d/ -f2 <<<"$REPO")"
[[ -n "$OWNER" && -n "$NAME" && "$NAME" != "$OWNER" ]] || usage
REPO="$OWNER/$NAME"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/issue-graph.html"
[[ $CDN -eq 1 ]] && TEMPLATE="$SCRIPT_DIR/issue-graph-cdn.html"
[[ -f "$TEMPLATE" ]] || { echo "Template not found: $TEMPLATE" >&2; exit 1; }
command -v gh >/dev/null || { echo "gh not found. Install it: https://cli.github.com" >&2; exit 1; }
gh auth status --hostname "$HOST" >/dev/null 2>&1 || { echo "gh is not logged in to $HOST. Run: gh auth login --hostname $HOST" >&2; exit 1; }

[[ -n "$OUT" ]] || OUT="issue-graph-${OWNER}_${NAME}.html"
if [[ $ALL -eq 1 ]]; then STATES=""; OPEN_JSON=false; else STATES="states:[OPEN],"; OPEN_JSON=true; fi

build_query(){ # $1 = 1 to include native dependencies (blockedBy)
  local DEPS=""
  [[ "$1" == 1 ]] && DEPS="blockedBy(first:50){nodes{number title state url repository{nameWithOwner}}}"
  QUERY="query(\$owner:String!,\$name:String!,\$endCursor:String){
  repository(owner:\$owner,name:\$name){
    issues(first:100,after:\$endCursor,${STATES}orderBy:{field:CREATED_AT,direction:ASC}){
      pageInfo{hasNextPage endCursor}
      nodes{
        number title state url body
        assignees(first:2){nodes{login}}
        $DEPS
      }
    }
  }
}"
}

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
echo "Fetching issues from $HOST/$REPO via gh…" >&2
fetch(){ gh api graphql --hostname "$HOST" --paginate --slurp -f query="$QUERY" -F owner="$OWNER" -F name="$NAME" > "$TMP/pages.json" 2> "$TMP/err.txt"; }
DEPS_OK=true
build_query 1
if ! fetch && grep -q 'blockedBy' "$TMP/err.txt"; then
  echo "Note: $HOST does not support native issue dependencies yet; dependencies will be read from “Depends on: …” / “Blocked by: …” lines in issue descriptions." >&2
  DEPS_OK=false; build_query 0
  fetch || true
fi
if [[ ! -s "$TMP/pages.json" ]] || ! grep -q '"data"' "$TMP/pages.json"; then
  cat "$TMP/err.txt" >&2
  if grep -qiE 'saml|sso' "$TMP/err.txt"; then
    echo "→ The organization requires SSO. Try: gh auth refresh -h $HOST, then authorize SSO in the browser." >&2
  fi
  exit 1
fi
if grep -q '"repository":null' "$TMP/pages.json"; then
  echo "Repository $REPO not found, or your gh account has no access to it." >&2; exit 1
fi

# Embed data into a copy of the template ("</" escaped so issue text cannot close the <script> tag)
{
  printf '{"repo":"%s","host":"%s","depsSupported":%s,"generatedAt":"%s","openOnly":%s,"pages":' "$REPO" "$HOST" "$DEPS_OK" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$OPEN_JSON"
  sed 's#</#<\\/#g' "$TMP/pages.json"
  printf '}'
} > "$TMP/data.json"

MARKER='<script type="application/json" id="embedded">null</script>'
grep -qF "$MARKER" "$TEMPLATE" || { echo "Template has no data marker — use the current $(basename "$TEMPLATE")." >&2; exit 1; }
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
