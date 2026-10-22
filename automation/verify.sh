#!/usr/bin/env bash
# Facilitator readiness check: one PASS/FAIL line per lab prerequisite.
set -uo pipefail

GITOPS_NS=${GITOPS_NS:-openshift-gitops}
SHOWROOM_NS=${SHOWROOM_NS:-showroom}
LAB_NS=${LAB_NS:-netpol-demo}
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
  local states
  states=$(oc -n "$GITOPS_NS" get applications.argoproj.io \
    -l demo.redhat.com/application=field-content \
    -o jsonpath='{range .items[*]}{.status.sync.status}/{.status.health.status}{"\n"}{end}') || return 1
  [[ -n "$states" ]] && ! grep -qv '^Synced/Healthy$' <<<"$states"
}

showroom_answers() {
  local host
  host=$(oc -n "$SHOWROOM_NS" get route showroom -o jsonpath='{.spec.host}') || return 1
  curl -fsk -o /dev/null "https://$host"
}

no_networkpolicies() {
  local out
  out=$(oc -n "$LAB_NS" get networkpolicies -o name) || return 1
  [[ -z "$out" ]]
}

model_api_returns_200() {
  [[ "$(oc -n "$LAB_NS" exec "deploy/$1" -- \
    curl -s -o /dev/null -m 3 -w '%{http_code}' http://model-api:8080/v1/models)" == 200 ]]
}

check "lab Applications are Synced/Healthy" apps_synced_healthy
check "Showroom route answers" showroom_answers
for d in model-api frontend other-app; do
  check "deployment $d available" oc -n "$LAB_NS" wait --for=condition=Available "deploy/$d" --timeout=10s
done
check "no NetworkPolicy in $LAB_NS (lab starts open)" no_networkpolicies
check "frontend gets 200 from the model API" model_api_returns_200 frontend
check "other-app gets 200 from the model API" model_api_returns_200 other-app

exit "$failed"
