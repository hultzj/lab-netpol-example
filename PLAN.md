# Default-deny networking for an AI application namespace — lab plan

Working document. Not rendered by Antora.

## Intake

- Audience and the customer question the lab answers: platform engineers.
  "If an AI app's pod is compromised, what else on the network can it reach —
  and can we prove it?"
- Products and pinned versions: OpenShift 4.x / 5.x with OVN-Kubernetes (the
  default network plugin), OpenShift GitOps (Argo CD). Images, pinned by exact
  tag plus index digest, confirmed on registry.access.redhat.com on 2026-10-22:
  - `ubi9/httpd-24:9.8-1792425938@sha256:a90a0ae3e1356cd740fb5e9dcfc298e912123f12f1078295d7038149d2c6684b`
    (the "model API": static JSON served by httpd on 8080, DocumentRoot `/var/www/html`, read from the image's httpd.conf)
  - `ubi9/ubi-minimal:9.8-1791898448@sha256:c4c285d42941ebb2bd4da878479008e1e4536bb599aad1dbe568f89de9053661`
    (the two clients; `/usr/bin/curl` and `/usr/bin/sleep` confirmed in the image layers)
- Tracks and time budget: one track, about 45 minutes (intro + pre-flight 5,
  Module 1 15, Module 2 25).
- Tenancy (dedicated cluster per participant, or shared with per-user namespaces):
  dedicated cluster per participant. One lab namespace, `netpol-demo`.
- Test cluster and git repo URL: test cluster exists, not contacted while
  drafting. Argo CD syncs `https://github.com/hultzj/lab-netpol-sample.git`,
  branch `main`, path `automation/argocd`.

## Lab map

| Module | Outcome | Time |
|---|---|---|
| 1. Verify the open baseline | Both clients reach the model API; no NetworkPolicy exists; a 404 control shows the probe tells "server answered" from "network blocked" | 15 min |
| 2. Default-deny, then allow one client | Both clients blocked by default-deny; one narrow allow restores only `frontend`; `other-app` stays blocked; policies removed and access restored | 25 min |

## Exercises

### Module 1, Exercise 1: Inspect the GitOps-deployed namespace

- **Teaches:** what Argo CD put in `netpol-demo` — one server, two clients, one Service, and their `app` labels (the labels policies select on).
- **Placement:** first exercise; everything later depends on these labels.
- **Draft steps:** `oc -n netpol-demo get deploy,svc,pods -L app`.
- **Negative control or break-and-restore:** none here (inspection).
- **Caveats (verified):** none yet; UNVERIFIED.

### Module 1, Exercise 2: Confirm there is no NetworkPolicy

- **Teaches:** with no policy selecting a pod, Kubernetes allows all traffic to it.
- **Placement:** before the reachability test, so learners know why both clients succeed.
- **Draft steps:** `oc -n netpol-demo get networkpolicy`.
- **Negative control or break-and-restore:** none.
- **Caveats (verified):** none yet; UNVERIFIED.

### Module 1, Exercise 3: Call the model API from both clients

- **Teaches:** the "compromised pod" (`other-app`) reaches the model API as easily as the legitimate caller (`frontend`).
- **Placement:** baseline evidence that Module 2 changes.
- **Draft steps:** `oc exec deploy/<client> -- curl -s -o /dev/null -m 3 -w '%{http_code}' http://model-api:8080/v1/models` for each client; expect `200`.
- **Negative control or break-and-restore:** Exercise 4.
- **Caveats (verified):** none yet; UNVERIFIED.

### Module 1, Exercise 4: Negative control — a path the server does not have

- **Teaches:** the probe distinguishes "server answered" (`200`, `404`) from "no answer" (`000`); later `000` results are network evidence, not an app error.
- **Placement:** right after the success case.
- **Draft steps:** same curl against `/v1/does-not-exist`; expect `404`.
- **Negative control or break-and-restore:** this is the negative control.
- **Caveats (verified):** none yet; UNVERIFIED.

### Module 2, Exercise 1: Apply default-deny ingress

- **Teaches:** an empty `podSelector` with `policyTypes: [Ingress]` selects every pod in the namespace and allows no ingress.
- **Placement:** first change in Module 2.
- **Draft steps:** `oc apply` a `default-deny-ingress` NetworkPolicy from a heredoc; `oc get networkpolicy`.
- **Negative control or break-and-restore:** break (restored in Exercise 5).
- **Caveats (verified):** none yet; UNVERIFIED. OVN-Kubernetes is expected to still allow kubelet probes, so pods stay Ready.

### Module 2, Exercise 2: Prove both clients are blocked

- **Teaches:** default-deny applies to the legitimate caller too; blocked traffic is dropped (curl times out, `000`, exit 28), not refused.
- **Placement:** immediately after default-deny.
- **Draft steps:** same curl from both clients; expect `000`.
- **Negative control or break-and-restore:** negative control for both clients.
- **Caveats (verified):** none yet; UNVERIFIED.

### Module 2, Exercise 3: Allow only frontend to the model API on 8080

- **Teaches:** NetworkPolicies are additive allow-lists; a second policy selecting `app=model-api` with `from: podSelector app=frontend` and `port 8080` opens exactly that path.
- **Placement:** after both clients are proven blocked.
- **Draft steps:** `oc apply` `allow-frontend-to-model-api`.
- **Negative control or break-and-restore:** Exercise 4 checks `other-app`.
- **Caveats (verified):** none yet; UNVERIFIED.

### Module 2, Exercise 4: Prove frontend works and other-app stays blocked

- **Teaches:** the allow is narrow: same server, same port, different source label, different result.
- **Placement:** the core evidence of the lab.
- **Draft steps:** curl from both; expect `200` and `000`.
- **Negative control or break-and-restore:** `other-app` is the matching deny.
- **Caveats (verified):** none yet; UNVERIFIED.

### Module 2, Exercise 5: Restore

- **Teaches:** removing the policies returns the namespace to allow-all; the change was the policies, not the workloads.
- **Placement:** last exercise, leaves the cluster as Module 1 found it.
- **Draft steps:** `oc delete networkpolicy ... --ignore-not-found`; curl from both, expect `200` twice.
- **Negative control or break-and-restore:** the restore half of the break.
- **Caveats (verified):** none yet; UNVERIFIED.

## Decisions

- Default-deny is **ingress only**. It answers "what can a compromised pod in
  this namespace reach inside the namespace" for the model API. Egress
  default-deny (DNS, external endpoints) is named in "What this lab does not
  prove" rather than taught, to fit 45 minutes.
- Clients are Deployments running `sleep infinity`; the learner runs curl
  inside them with `oc exec`, so the Showroom terminal (another namespace) is
  never on the tested network path.
- Participants create the NetworkPolicies; they are not in the chart, so
  Argo CD does not track, revert, or prune them, and no `ignoreDifferences`
  is needed.
- The Showroom terminal gets a custom Role in `netpol-demo` (read pods,
  services, deployments, events, the namespace; `pods/exec`; manage
  NetworkPolicies), not ClusterRole `edit`. `edit` would let the participant
  relabel `other-app` as `frontend`, which is exactly the bypass the
  reference page warns about.
- The mermaid diagram on the Module 2 page uses literal names: the pinned
  mermaid extension (0.0.9) applies `subs=` to the string of the subs value,
  not to the diagram source, so attributes cannot be used there.
