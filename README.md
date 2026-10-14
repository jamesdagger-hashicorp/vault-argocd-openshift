# Vault platform

Helm wrapper chart for HashiCorp Vault Enterprise on OpenShift, delivered by ArgoCD from a Git repository.

- `vault-platform/`: the chart (upstream `hashicorp/vault` as a dependency, plus Route, Certificate and a per-namespace auth-delegator ClusterRoleBinding)
- `docs/installation.md`: open items, prerequisites, ArgoCD Application, rendering locally, resource quotas
- `docs/exploitation.md`: operations (init, health, backup, rotation, upgrades)
- `docs/byok.md`: placeholder for a future use case (not yet defined)

Scope: deployment only. Initialisation and configuration (auth methods, policies, secret engines) are not covered yet.

Start with the open-items table in `docs/installation.md`.
