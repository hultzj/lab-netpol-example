#!/usr/bin/env bash
# Facilitator readiness check: one PASS/FAIL line per lab prerequisite.
set -uo pipefail

GITOPS_NS=${GITOPS_NS:-openshift-gitops}
SHOWROOM_NS=${SHOWROOM_NS:-showroom}
LAB_NS=${LAB_NS:-netpol-demo}
# The parent Application name; children are <LAB_APP>-showroom and <LAB_APP>-prereqs.
LAB_APP=${LAB_APP:-lab-netpol-sample}
# Participants run every step as this identity; check as it, not as the facilitator.
TERMINAL_SA="system:serviceaccount:${SHOWROOM_NS}:showroom"
failed=0

check() {
  local name=$1
  shift
  if "$@" >/dev/null 2>&1; then
    echo "PASS: $name"
  else
    echo "FAIL: $name"
    failed=1
  fi
}

apps_synced_healthy() {
  local apps
  apps=$(oc -n "$GITOPS_NS" get applications.argoproj.io \
    -l demo.redhat.com/application=field-content \
    -o jsonpath='{range .items[*]}{.metadata.name} {.status.sync.status}/{.status.health.status}{"\n"}{end}') || return 1
  # Both children must exist, and this lab's Applications (exact names) must be Synced/Healthy.
  awk -v app="$LAB_APP" '
    $1 == app "-showroom" { s = 1 }
    $1 == app "-prereqs" { p = 1 }
    ($1 == app || $1 == app "-showroom" || $1 == app "-prereqs") && $2 != "Synced/Healthy" { bad = 1 }
    END { exit !(s && p && !bad) }
  ' <<<"$apps"
}

showroom_answers() {
  local host
  host=$(oc -n "$SHOWROOM_NS" get route showroom -o jsonpath='{.spec.host}') || return 1
  curl -fsk --max-time 10 -o /dev/null "https://$host"
}

no_networkpolicies() {
  local out
  out=$(oc -n "$LAB_NS" get networkpolicies -o name) || return 1
  [[ -z "$out" ]]
}

model_api_returns_200() {
  local code
  code=$(oc --as "$TERMINAL_SA" -n "$LAB_NS" exec "deploy/$1" -- \
    curl -s -o /dev/null -m 3 -w '%{http_code}' http://model-api:8080/v1/models) && [[ $code == 200 ]]
}

check "lab Applications are Synced/Healthy" apps_synced_healthy
check "Showroom route answers" showroom_answers
for d in model-api frontend other-app; do
  check "deployment $d available" oc -n "$LAB_NS" wait --for=condition=Available "deploy/$d" --timeout=10s
done
check "no NetworkPolicy in $LAB_NS (lab starts open)" no_networkpolicies
check "frontend gets 200 from the model API (as the terminal)" model_api_returns_200 frontend
check "other-app gets 200 from the model API (as the terminal)" model_api_returns_200 other-app
for verb in create delete; do
  check "terminal can $verb NetworkPolicies" \
    oc auth can-i "$verb" networkpolicies.networking.k8s.io -n "$LAB_NS" --as "$TERMINAL_SA"
done

exit "$failed"
