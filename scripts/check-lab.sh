#!/usr/bin/env bash
# Lab contract checks the Antora build cannot do. Run after `npm run build`.
# Usage: bash scripts/check-lab.sh [--draft]
# --draft skips the "no unverified steps" check, for use before the live verification pass.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

draft=false
[[ "${1:-}" == "--draft" ]] && draft=true
pages=content/modules/ROOT/pages
nav=content/modules/ROOT/nav.adoc
failed=0
fail() { printf 'check-lab: %s\n' "$*" >&2; failed=1; }

if grep -rIn --exclude-dir={node_modules,www,.git,.cache,evidence,.xreview} \
     --exclude=check-lab.sh 'CHANGE-ME' . >&2; then
  fail "scaffold placeholders remain (CHANGE-ME)"
fi

for page in "$pages"/*.adoc; do
  grep -Fq "xref:$(basename "$page")[" "$nav" || fail "$page is not in nav.adoc"
done

for page in "$pages"/*-module-*.adoc; do
  [[ -e "$page" ]] || { fail "no module pages (*-module-*.adoc) in $pages"; break; }
  for section in '== Learning objectives' '== Evidence checkpoint' '.Answer key'; do
    grep -Fxq "$section" "$page" || fail "$page is missing '$section'"
  done
done

# Every participant command (role="execute") needs an Expected result before the next block or heading.
for page in "$pages"/*.adoc; do
  awk -v f="$page" '
    pending && (/^\[source/ || /^=+ /) { print f ":" line ": execute block without an Expected result"; bad = 1; pending = 0 }
    /^\[source.*role="?execute"?/ { pending = 1; line = FNR; next }
    pending && /^Expected result/ { pending = 0 }
    END { if (pending) { print f ":" line ": execute block without an Expected result"; bad = 1 }; exit bad }
  ' "$page" >&2 || failed=1
done

# Argo CD consumes these charts straight from main, so they must render.
for chart in automation/argocd automation/argocd/components/*/; do
  # Components get the parent's values, as the parent passes them through.
  helm template lab "$chart" -f automation/argocd/values.yaml --set deployer.domain=apps.example.com >/dev/null ||
    fail "$chart does not render"
done

# A defined attribute still shown as {name} in the HTML was never substituted:
# its block lacks subs="attributes+" (Asciidoctor does not warn about that).
if [[ ! -d www ]]; then
  fail "no www/ to inspect; run npm run build first"
else
  names=$(awk '/^  attributes:/ {a = 1; next} a && /^    [A-Za-z0-9_-]+:/ {sub(/^ +/, ""); sub(/:.*/, ""); print}' \
    content/antora.yml | paste -sd'|' -)
  if [[ -n "$names" ]] && grep -rnoE "\{($names)\}" www --include='*.html' >&2; then
    fail "attributes rendered literally; add subs=\"attributes+\" to those blocks"
  fi
fi

# The field-content Showroom builder (quay.io/rhpds/antora) has no mermaid extension.
if grep -n '^\[mermaid' "$pages"/*.adoc >&2; then
  fail "[mermaid] blocks do not render in Showroom; use a table or numbered list"
fi

if ! $draft && grep -n '^// UNVERIFIED' "$pages"/*.adoc >&2; then
  fail "steps not yet verified on a live cluster (// UNVERIFIED)"
fi

[[ $failed -eq 0 ]] && echo "check-lab: OK$($draft && echo ' (draft)')"
exit "$failed"
