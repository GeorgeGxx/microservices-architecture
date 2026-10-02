# 🌿 Enterprise Git Branching Strategy & Team Collaboration Manual

> [!TIP]
> 🧭 **[Enterprise Platform Hub](../../README.md)** > **03. DevSecOps & Testing** > `GIT_WORKFLOW_AND_COLLABORATION.md`

> Exhaustive guide to the project's hybrid Trunk-Based & Environment Branching workflow, branch protection policies, collaborative Git divergence resolution, and disaster recovery playbooks.

---

## 🎯 Architecture Overview & Branching Model

This microservices repository adopts a **Hybrid Trunk-Based with Environment Promotion** model (tailored for multi-cloud DevSecOps and Kubernetes GitOps). This architecture balances rapid developer iteration with strict security, automated testing gates, and declarative continuous deployment:

```mermaid
gitGraph
    commit id: "v1.0.0"
    branch develop
    checkout develop
    commit id: "Initial-Dev"
    branch feature/led
    checkout feature/led
    commit id: "feat: add LED status"
    commit id: "test: verify navbar"
    checkout develop
    merge feature/led id: "PR #42: Squash & Merge"
    branch staging
    checkout staging
    merge develop id: "Promote to Staging"
    commit id: "QA: Newman + k6 Pass"
    checkout main
    merge staging id: "Release v1.1.0"
    commit id: "Istio Canary 10% -> 100%"
```

### 🗺️ Branch to Environment & Cloud Mapping Matrix

| Git Branch | Target Environment | Kubernetes Namespace | Target Clouds / Clusters | Primary Responsibility |
| :--- | :--- | :--- | :--- | :--- |
| **`feature/*`**, **`fix/*`** | Local Workspace | N/A | Local Docker / Minikube | Isolated unit work, feature prototyping, local tests. |
| **`develop`** | **`dev`** | `dev` | • Minikube (Local)<br/>• AWS EKS Dev<br/>• Azure AKS Dev<br/>• GCP GKE Dev | **Integration Trunk:** Continuous integration, daily developer merges, automated ArgoCD sync, rapid feedback. |
| **`staging`** | **`staging`** | `staging` | • AWS EKS Staging<br/>• Azure AKS Staging<br/>• GCP GKE Staging | **Quality & Security Gate:** Medium-performance tier (2 replicas), Newman API suite, Cypress E2E, k6 load testing, OWASP ZAP DAST. |
| **`master`** / **`main`** | **`production`** | `production` | • AWS EKS Prod<br/>• Azure AKS Prod<br/>• GCP GKE Prod | **Production Release:** High-availability HA tier (3-10 HPA replicas), Istio Canary traffic routing (90/10), Cloud Armor/WAF. |

---

## 🔄 Daily Developer Workflow Playbook

### Step 1: Start from the Latest Integration Trunk
Always branch off an up-to-date `develop` branch:
```bash
git checkout develop
git pull origin develop
git checkout -b feature/user-checkout-toasts
```

### Step 2: Write Clean, Atomic Commits (Conventional Commits)
Use standard prefix tags to facilitate automated changelog generation and semantic versioning:
* `feat:` A new user-facing feature (e.g., `feat(frontend): add lateral toast notifications on order placement`)
* `fix:` A bug fix (e.g., `fix(gateway): resolve DNS upstream resolution in nginx proxy`)
* `refactor:` Code restructuring without changing functional behavior
* `test:` Adding or adjusting automated unit, integration, or smoke tests
* `docs:` Documentation updates or architectural diagram regeneration
* `chore:` Build dependencies, package versions, or tooling scripts

```bash
git add frontend/src/app/features/orders/checkout.component.ts
git commit -m "feat(frontend): trigger lateral toast notifications on order confirmation"
```

### Step 3: Keep Your Feature Branch Fresh (Rebase, Don't Merge)
Avoid creating noisy merge bubbles. Rebase your feature branch against upstream changes:
```bash
git fetch origin
git rebase origin/develop
```
> [!TIP]
> If you encounter conflicts during rebase, resolve the conflicting files, stage them (`git add <file>`), and proceed with `git rebase --continue`. Never run `git rebase --skip` unless you intentionally want to discard the commit.

### Step 4: Submit a Pull Request (PR)
1. Push your branch to remote:
   ```bash
   git push -u origin feature/user-checkout-toasts
   ```
2. Open a Pull Request targeting **`develop`**.
3. Automated CI triggers:
   * **Unit Tests & JaCoCo Code Coverage:** Asserts minimum 80% line coverage.
   * **SAST & Secret Detection:** Gitleaks, Semgrep, and Trivy filesystem scan.
   * **OPA Policy Check:** Verifies Kubernetes resource limits and container security contexts.
4. Once approved, use **Squash and Merge** or **Rebase and Merge** to maintain a linear Git history on `develop`.

> [!NOTE]
> For the complete list of acceptance criteria, contract validation, and quality gates required before opening and merging a PR, consult [QUALITY_GATES_AND_DOD.md](./QUALITY_GATES_AND_DOD.md).

---

## 🛡️ Branch Protection Rules & The Golden Rule

### 🚫 The Golden Rule of Shared Branches
> **NEVER execute `git reset --hard` followed by a `git push --force` on shared collaboration branches (`develop`, `staging`, `main`/`master`).**

On GitHub, Azure DevOps, and Bitbucket, configure branch protection rules for `develop`, `staging`, and `main`:
1. **Require pull request reviews** before merging (minimum 1 peer review).
2. **Require status checks to pass** before merging (CI tests, Trivy, Gitleaks).
3. **Do not allow bypassing the above settings**.
4. **Block Force Pushes:** Enable *"Do not allow force pushes"* to protect team members from accidental history rewrites.

---

## 💥 Troubleshooting Git Drift, Force-Pushes & Resets

### What Happens When a Teammate Force-Pushes After a `git reset`?

Suppose **Developer A** made commits `C1 -> C2 -> C3` and pushed to `develop`.
**Developer B** pulled, so Developer B now has `C3` locally.

If Developer A subsequently resets their local branch to `C2` and force-pushes (`git push --force`), the remote branch now points to `C2`.

When **Developer B** later runs `git pull`:
1. **Modern Git (v2.27+) detects divergent branches:**
   ```text
   fatal: Need to specify how to reconcile divergent branches.
   hint: You have divergent branches and need to specify how to reconcile them.
   hint: You can do so by running one of the following commands...
   ```
2. **If Developer B performs a standard merge (`git pull --no-rebase`):**
   Git treats `C3` as Developer B's own new local commit. Git merges `C3` back in with a merge commit, **accidentally resurrecting the exact buggy commit that Developer A deleted!**
3. **If Developer B had modified the same files:**
   Git reports merge conflicts across every line altered between `C2` and `C3`.

---

### 🧯 Resolution Playbooks for Developer B

Depending on whether Developer B has unpushed commits they need to preserve, follow the appropriate recovery procedure:

---

#### 🟢 Scenario 1: Developer B has NO local commits to keep (90% of cases)
Developer B only pulled the old commit and has not committed new work on top of it.

**Solution:** Discard the orphan local commits and snap the local branch directly to the updated remote state:

```bash
# 1. Download the real remote state without merging
git fetch origin

# 2. Hard reset your local tracking branch to match the remote exactly
git reset --hard origin/develop

# 3. Clean untracked build artifacts or transient files
git clean -fd
```
> [!NOTE]
> This instantly cleans your working tree and aligns your repository with the remote branch, erasing the phantom commit.

---

#### 🟡 Scenario 2: Developer B HAS local work (`C4`, `C5`) committed on top of the erased commit (`C3`)
Developer B built features on top of `C3` and cannot afford to lose their progress.

```text
Remote:           C1 ---> C2 (HEAD)
Developer B:      C1 ---> C2 ---> C3 (erased remotely) ---> C4 ---> C5 (HEAD)
Desired Result:   C1 ---> C2 ---> C4' ---> C5' (HEAD)
```

##### Option A: Surgical Transplant via `git rebase --onto` (Recommended)
`git rebase --onto` instructs Git: *"Take all commits from after `<ERASED_COMMIT>` up to my current branch, and replay them directly on top of `origin/develop`"*:

```bash
# 1. Fetch remote tracking branches
git fetch origin

# 2. Transplant commits C4 and C5 on top of new origin/develop, skipping C3:
git rebase --onto origin/develop <ERASED_COMMIT_HASH> develop

# 3. If conflicts arise, resolve them and continue:
git add <resolved-files>
git rebase --continue
```

##### Option B: Safe Branching & Cherry-Pick (Fail-Safe Method)
If you prefer not to use complex rebase arguments, this visual method guarantees zero data loss:

```bash
# 1. Create a safety backup branch containing your current work:
git branch backup/my-work

# 2. Reset your main branch to match the clean remote:
git fetch origin
git reset --hard origin/develop

# 3. Cherry-pick only your legitimate commits (e.g. C4 and C5):
git cherry-pick <HASH_OF_C4>
git cherry-pick <HASH_OF_C5>

# 4. Verify your work compiles and runs:
# (Once verified, safely delete the temporary backup branch)
git branch -D backup/my-work
```

---

## ⏪ Safe History Modifications: `git revert` vs. `git reset`

To avoid causing sync issues for team members, choose the right undo tool based on the branch context:

| Criteria | `git revert <commit>` | `git reset [--hard\|--soft] <commit>` |
| :--- | :--- | :--- |
| **History Behavior** | **Appends** a new inverse commit that cancels out the changes. | **Deletes / moves** branch pointers backward in time. |
| **Safety for Remote** | 🟢 **100% Safe:** No force-push required. Team members receive clean updates on standard `git pull`. | 🔴 **Destructive:** Requires `git push --force`. Will cause branch drift for teammates. |
| **Where to Use** | Shared branches: `develop`, `staging`, `main`, `master`. | Private, unmerged personal branches (`feature/*`, `fix/*`). |
| **Audit Trail** | Preserves full auditability of the incident and correction. | Erases history completely. |

### Example: Reverting a Broken Commit on `develop`
```bash
# Identify the problematic commit SHA:
git log --oneline -n 5

# Create a clean revert commit:
git revert a98a716 -m "revert: rollback broken payment payload validator"

# Push safely without force:
git push origin develop
```

---

## ⚙️ Recommended Local Git Configuration

Run these commands on your workstation to prevent common Git merge anomalies:

```bash
# 1. Automatically rebase on git pull (prevents unnecessary merge bubbles):
git config --global pull.rebase true

# 2. Automatically stash and restore uncommitted changes during rebase:
git config --global rebase.autoStash true

# 3. Enable Git's reuse recorded resolution (auto-resolves recurring conflicts):
git config --global rerere.enabled true

# 4. Set the default initial branch to 'main':
git config --global init.defaultBranch main

# 5. Convenient colorized log alias:
git config --global alias.lg "log --color --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit"
```
