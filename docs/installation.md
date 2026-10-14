# Installation

Deploys HashiCorp Vault Enterprise (3-node Raft) to OpenShift using the `vault-platform` wrapper chart.

| Environment | Namespace    | Values file                         |
|-------------|--------------|-------------------------------------|
| DEV         | `vault-dev`  | `values.yaml` + `values-dev.yaml`   |
| PROD        | `vault`      | `values.yaml` + `values-prod.yaml`  |

Both environments run on the same cluster. They share nodes and failure domain; see the note at the end.

## Open items (fill in before first deploy)

Search the repo for `<` placeholders. The chart refuses to render (and ArgoCD refuses to sync) while the route host or issuer still contains one, with an error naming the value. Current list:

| Placeholder                  | Where                     | Notes |
|------------------------------|---------------------------|-------|
| Upstream chart version       | `Chart.yaml`              | Pinned to `0.34.1`. Review before first deploy, run `helm dependency update` and commit `Chart.lock`. |
| `<ISSUER_NAME>`, `<Issuer\|ClusterIssuer>` | `values.yaml` | Existing cert-manager issuer. Confirm its type; see prerequisite 1. |
| `<CLUSTER_APPS_DOMAIN>`      | `values-dev/prod.yaml`    | Route hostnames. |
| Seal configuration           | `values.yaml` raft config | Auto-unseal not yet chosen. Shamir (manual unseal) until then. |

## Prerequisites

Cluster side, per namespace (`vault`, `vault-dev`):

1. **cert-manager** installed, with an issuer usable from both namespaces (a ClusterIssuer, or the same Issuer in each). The issuer must:
   - put the issuing CA in `ca.crt` of the `vault-tls` Secret. Raft joins (`leader_ca_cert_file`) and the CLI (`VAULT_CACERT`) read it. CA and Vault issuers do this; ACME issuers do not, and cannot issue the internal names below anyway.
   - allow the SANs in `templates/certificate.yaml`: the Route host, `localhost`, `127.0.0.1`, and the internal service and pod names in short, namespaced, `.svc` and `.svc.cluster.local` forms. Check for any cert-manager approver policy that restricts names or IPs.
   - be trusted by Vault's clients: anyone calling the Route sees this certificate directly (passthrough), so its CA must be in their trust store.
2. **License secret** named `vault-license` with key `license`:
   `oc create secret generic vault-license --from-file=license=<path-to-license-file> -n <namespace>`
   Replace with Sealed Secrets or External Secrets if you use one. Never commit the license.
3. **ArgoCD permissions** on both namespaces. If ArgoCD is in another namespace (for example `openshift-gitops`), the namespaces need the `argocd.argoproj.io/managed-by=<argocd-namespace>` label or equivalent RoleBindings.
   The chart also creates one cluster-scoped object per environment: ClusterRoleBinding `<namespace>-server-binding` (`vault-dev-server-binding`, `vault-server-binding`) to `system:auth-delegator`, for Vault's Kubernetes auth method. ArgoCD needs permission to create ClusterRoleBindings, and the AppProject must allow it (`clusterResourceWhitelist`, group `rbac.authorization.k8s.io`). A namespace-scoped ArgoCD instance usually cannot. If so, set `platform.authDelegator.enabled: false` and have a cluster admin create it:
   ```
   oc create clusterrolebinding <namespace>-server-binding --clusterrole=system:auth-delegator --serviceaccount=<namespace>:vault
   ```
4. **Image pull access** to the registry in `values.yaml`.
5. **Storage class** for Raft data. The default is used unless `vault.server.dataStorage.storageClass` is set.

## ArgoCD Application

The Application manifests are not in this repo. Example for DEV (PROD is the same with `name: vault`, `values-prod.yaml` and `namespace: vault`):

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: vault-dev
  namespace: <ARGOCD_NAMESPACE>
spec:
  project: default
  source:
    repoURL: <GIT_REPO_URL>
    targetRevision: <BRANCH_OR_TAG>
    path: vault-platform
    helm:
      releaseName: vault          # required: the chart assumes this name
      valueFiles:
        - values.yaml
        - values-dev.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: vault-dev
  # No automated sync for the first deployment: sync manually and watch.
```

Notes:

- `releaseName: vault` is required in both Applications (Raft addresses and certificate names depend on it).
- Pods will be Running but sealed until Vault is initialised and unsealed (see `exploitation.md`), so ArgoCD will not show a fully healthy state before then.
- ArgoCD must fetch the chart dependency (`helm.releases.hashicorp.com`). If the first sync fails with a `helm dependency build` error, vendor the chart: run `helm dependency build vault-platform` on a machine with internet, then commit `vault-platform/charts/*.tgz` and `Chart.lock` and remove `vault-platform/charts/` from `.gitignore`.

## Rendering locally

```
helm dependency build vault-platform
helm template vault vault-platform -n vault-dev -f vault-platform/values-dev.yaml
```

The chart's own `values.yaml` is always loaded first, so pass only the environment file.

## Resource quotas

If the projects have a ResourceQuota, it must hold 3 Vault pods plus their data volumes. The values files are sized as follows.

**DEV (`vault-dev`).** `values-dev.yaml` is sized to fit this quota:

| Resource               | `vault-dev` quota | Used by 3 pods |
|------------------------|-------------------|----------------|
| pods                   | 5                 | 3              |
| persistentvolumeclaims | 6                 | 3              |
| requests.storage       | 30Gi              | 15Gi (3 x 5Gi) |
| requests.cpu           | 500m              | 450m           |
| requests.memory        | 4Gi               | 3Gi            |
| limits.cpu             | 2                 | 1800m          |
| limits.memory          | 4Gi               | 3Gi            |

Per pod: 150m CPU request and 600m limit, 1Gi memory request equal to limit, a 5Gi data volume. Audit logs go to stdout, so no audit volumes are used.

- With `requests.cpu` (500m) below `limits.cpu` (2), CPU is burstable (limit 4x request). If `requests.cpu` allows 2, switch to 500m request = limit, which is HashiCorp's guidance for shared nodes.
- Memory request equals limit so the pod is not evicted ahead of others under node pressure.

**PROD (`vault`).** Not in scope for deployment yet. `values-prod.yaml` uses HashiCorp's small-cluster sizing: per pod 2 CPU request and limit, 8Gi memory request, 16Gi memory limit, and a 100Gi data volume. Minimum quota for 3 pods:

| Resource               | Minimum `vault` quota |
|------------------------|-----------------------|
| pods                   | 5                     |
| persistentvolumeclaims | 6                     |
| requests.storage       | 300Gi                 |
| requests.cpu           | 6                     |
| requests.memory        | 24Gi                  |
| limits.cpu             | 6                     |
| limits.memory          | 48Gi                  |

The StatefulSet uses `OnDelete` updates (one pod replaced at a time, by hand), so no surge headroom is needed. Add headroom for growth if wanted.

## Notes

- DEV and PROD on one cluster means a cluster outage takes out both. Confirm this is acceptable before going live.
- Anti-affinity stays on in the DEV and PROD values (the upstream default), so each environment needs at least 3 schedulable nodes.
