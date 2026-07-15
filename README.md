# ShopList — End-to-End DevOps Pipeline

**Nechama Spiegler**
[Live Demo](http://34.244.59.62:30080) · [GitHub Repository](https://github.com/nechami-abc/DevOps-final-project)

A full-stack shopping-list application, deployed to AWS through a fully automated Infrastructure-as-Code and CI/CD pipeline — from `git push` to a running Kubernetes cluster.

---

## Overview

This is a complete DevOps lifecycle built and executed end-to-end — not just configuration files sitting in a repo, but infrastructure that was actually provisioned, an app that was actually built and deployed, and a pipeline that was actually run (see [pipeline evidence](#-pipeline-runs--proof-it-actually-ran) below).

| Skill | How it shows up here |
|---|---|
| **Infrastructure as Code** | Terraform provisions an AWS EC2 instance, security group, and IAM role from scratch |
| **Configuration Management** | Ansible installs Minikube and deploys the app onto the freshly created machine |
| **Containerization** | Multi-service app (Flask API + static frontend + PostgreSQL) fully Dockerized |
| **Orchestration** | Kubernetes manifests manage Deployments, Services, ConfigMaps, Secrets, and persistent storage |
| **CI/CD** | GitHub Actions builds, tests, pushes to a container registry, and rolls out updates automatically |
| **Cloud Cost Discipline** | Infrastructure is provisioned on demand and torn down with a dedicated destroy pipeline |

---

## Architecture

```
┌─────────────┐      push to main      ┌──────────────────────┐
│  Developer  │ ──────────────────────▶ │   GitHub Actions CI   │
└─────────────┘                         └──────────┬───────────┘
                                                     │ build + push images
                                                     ▼
                                         ┌──────────────────────┐
                                         │  GitHub Container     │
                                         │  Registry (ghcr.io)   │
                                         └──────────┬───────────┘
                                                     │ deploy over SSH
                                                     ▼
┌─────────────────────────── AWS EC2 (Terraform-provisioned) ───────────────────────────┐
│                                                                                          │
│                         Minikube (installed via Ansible)                                │
│   ┌────────────┐      ┌────────────┐      ┌──────────────┐                            │
│   │  Frontend   │ ───▶ │  Backend    │ ───▶ │  PostgreSQL   │                            │
│   │  (Nginx)    │      │  (Flask)    │      │  (StatefulSet)│                            │
│   └────────────┘      └────────────┘      └──────────────┘                            │
│         ▲ NodePort :30080                                                               │
└─────────┼───────────────────────────────────────────────────────────────────────────────┘
          │
    🌍 http://34.244.59.62:30080
```

---

## Tech Stack

**Application**
- Backend: Python (Flask) + `psycopg2`, REST API for products
- Frontend: HTML / CSS / vanilla JavaScript, served via Nginx
- Database: PostgreSQL

**Infrastructure & DevOps**
- **Terraform** — provisions the AWS EC2 instance, security group, and IAM/SSM role
- **Ansible** — installs Minikube on the instance and deploys the app onto it
- **Docker** — containerizes the backend and frontend
- **Kubernetes** (via Minikube) — Deployments, Services, ConfigMaps, Secrets, PVC, namespace isolation
- **GitHub Actions** — CI/CD: build → smoke test → push to GHCR → verify → deploy
- **GitHub Container Registry (ghcr.io)** — image hosting

---

## How the Pipeline Works

### 1. Create Infra
Terraform spins up a free-tier EC2 instance (Ubuntu 22.04) with a security group open on port `22` (SSH) and `30080` (app NodePort), plus an IAM role for SSM access. Ansible then installs Minikube on the instance and performs the first deployment.

### 2. Confirm Infra
A validation run confirms the instance is reachable and the cluster is healthy before moving on to continuous deployment.

### 3. Build, Push & Deploy (CI/CD)
On every push to `main` that touches the app code:
1. **Build** — separate jobs build the backend and frontend Docker images
2. **Smoke test** — the backend image is run once to confirm its dependencies import correctly
3. **Push** — both images are pushed to GitHub Container Registry, tagged with the short commit SHA
4. **Verify** — the pipeline pulls both images back down to confirm they landed in the registry
5. **Deploy** — over SSH, `kubectl set image` rolls the new images out to the live Deployments, then waits for `rollout status` to confirm success

### 4. Destroy Infra
A dedicated plan-then-confirm pipeline tears down all AWS resources once the work is documented, so no idle infrastructure is left running up costs.

---

## Pipeline Runs

| Stage | Run | Result |
|---|---|---|
| Create Infra | [Run #29347253949](https://github.com/nechami-abc/DevOps-final-project/actions/runs/29347253949) | Passed |
| Confirm Infra | [Run #29347582185](https://github.com/nechami-abc/DevOps-final-project/actions/runs/29347582185) | Passed |
| Build, Push & Deploy | [Run #29346993138](https://github.com/nechami-abc/DevOps-final-project/actions/runs/29346993138) | Passed |
| Destroy Infra — Plan | [Run #29420309828](https://github.com/nechami-abc/DevOps-final-project/actions/runs/29420309828) | Passed |
| Destroy Infra — Confirm | [Run #29420517904](https://github.com/nechami-abc/DevOps-final-project/actions/runs/29420517904) | Passed |

The application was live and verified running at `http://34.244.59.62:30080`; a screenshot is included in the repository.

---

## Project Structure

```
.
├── app/
│   ├── backend/          # Flask REST API
│   └── frontend/         # HTML/CSS/JS + Nginx
├── docker/                # docker-compose for local dev
├── terraform/             # AWS infrastructure definitions
├── ansible/                # Provisioning & deployment playbooks
├── kubernetes/             # K8s manifests (Deployments, Services, PVC, Secrets)
└── .github/workflows/      # CI/CD pipeline definitions
```

---

## Notes on Design Decisions

- **Infrastructure creation is manual, not automatic.** `ansible/provision.sh` is intentionally run by hand rather than triggered by a pipeline, so cloud resources — and their cost — are never created as a side effect of a routine `git push`.
- **Deployment is decoupled from provisioning.** The CI/CD workflow updates the running application over SSH via `kubectl set image`; it does not touch Terraform or AWS credentials, keeping the "ship code" and "manage infrastructure" concerns separate.
- **Resources are torn down deliberately.** A dedicated plan-then-confirm destroy pipeline removes all AWS resources once the work is verified and documented.

The pipeline links above point to completed GitHub Actions runs against real AWS infrastructure, not just workflow definitions — the project was built, deployed, and verified end to end.

---

**Nechama Spiegler**
[GitHub Repository](https://github.com/nechami-abc/DevOps-final-project)
