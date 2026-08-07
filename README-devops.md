# DevOps Setup — Spring PetClinic

End-to-end pipeline for this repo: **GitHub Actions (CI/CD) → GHCR → Argo CD (GitOps) → Kubernetes**, with **Prometheus + Grafana** monitoring the app.

```
 push to main
      │
      ▼
┌─────────────────────────────┐
│ GitHub Actions (ci-cd.yml)  │
│  1. mvn verify (build+test) │
│  2. build image → GHCR      │
│  3. bump tag in k8s/        │ ── commit ──┐
└─────────────────────────────┘             │
                                            ▼
                              ┌───────────────────────────┐
                              │ Argo CD (watches k8s/)     │
                              │  auto-sync to cluster      │
                              └───────────────────────────┘
                                            │
                          ┌─────────────────┴─────────────────┐
                          ▼                                     ▼
                  petclinic + postgres            kube-prometheus-stack
                   (k8s/*.yml)                    (Prometheus/Grafana/Alertmanager)
                          │                                     ▲
                          └──────── /actuator/prometheus ───────┘
                                     (ServiceMonitor)
```

## What's included

| File | Purpose |
|------|---------|
| `Dockerfile` | Multi-stage build (Maven→JRE, Java 17). The CI builds this. |
| `.github/workflows/ci-cd.yml` | Build, test, push image to GHCR, bump GitOps tag. |
| `k8s/petclinic.yml` | App Deployment+Service (image line is auto-bumped by CI). |
| `argocd/petclinic-app.yaml` | Argo CD Application for the app. |
| `argocd/monitoring-app.yaml` | Argo CD Application for the monitoring stack. |
| `k8s/monitoring/values.yaml` | Helm values for kube-prometheus-stack (+ Spring dashboards). |
| `k8s/monitoring/servicemonitor.yaml` | Tells Prometheus to scrape PetClinic. |
| `pom.xml` change | Adds `micrometer-registry-prometheus` (required for metrics). |

## One required code change

Your `pom.xml` has `spring-boot-starter-actuator` but **not** the Prometheus registry, so `/actuator/prometheus` won't exist until you add:

```xml
<dependency>
  <groupId>io.micrometer</groupId>
  <artifactId>micrometer-registry-prometheus</artifactId>
  <scope>runtime</scope>
</dependency>
```

(Place it right after the actuator dependency. A ready-to-use `pom.xml` is provided.)

## Setup

### 1. Copy files into the repo
Place `Dockerfile`, `.github/`, `argocd/`, and the new `k8s/monitoring/` files at the repo root, replace `k8s/petclinic.yml`, and apply the `pom.xml` change. Commit and push to `main`.

### 2. CI/CD (GitHub Actions)
No secrets required — the workflow pushes to GHCR using the built-in `GITHUB_TOKEN`. After the first run, make the GHCR package public (or grant your cluster a pull secret) under your repo's **Packages**.

The pipeline auto-runs on push to `main`. PRs run build+test only.

### 3. Install Argo CD
```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Get the initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo
# UI:
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

### 4. Register the apps
```bash
kubectl apply -f argocd/petclinic-app.yaml
kubectl apply -f argocd/monitoring-app.yaml
```
Argo CD will create the `petclinic` and `monitoring` namespaces and sync everything. From now on, every push to `main` rebuilds the image and Argo CD rolls it out automatically.

### 5. Access Grafana
```bash
kubectl -n monitoring port-forward svc/kps-grafana 3000:80
# login: admin / admin  (change this in k8s/monitoring/values.yaml)
```
Prometheus scrapes PetClinic via the ServiceMonitor; the **JVM (Micrometer)** and **Spring Boot** dashboards are pre-loaded, alongside the default cluster/node/pod dashboards.

## Notes / hardening
- **Grafana password** and **Postgres credentials** (`k8s/db.yml`) are demo values — move them to Secrets (e.g. Sealed Secrets / External Secrets) for anything real.
- Prometheus uses ephemeral storage here; switch to a PVC in `values.yaml` for persistence.
- The CI registry is GHCR. To use Docker Hub instead, swap the login/tags in `ci-cd.yml` and add `DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN` secrets.
