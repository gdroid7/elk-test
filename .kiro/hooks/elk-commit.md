---
name: elk-commit
description: >
  After elk-setup or kibana-agent writes files, prompt user to commit and
  push. Checks git status for ELK-related files only. Never auto-commits.
trigger: userMessage
condition: >
  Only activate if git status shows uncommitted changes in:
  elk/, .env, Makefile, ELK_README.md, kibana/, elk/demo-logs.sh
---

# elk-commit — Commit & Push Prompt

Runs silently unless ELK files have uncommitted changes. Never auto-commits.

## Rules
- Never commit without explicit user confirmation.
- Never use `git push --force`.
- If no ELK changes detected → do nothing, no output.

---

## Step 1: Check for ELK changes

Run: `git status --short`

Filter output for lines containing: `elk/`, `.env`, `Makefile`, `ELK_README.md`, `kibana/`, `demo-logs.sh`

If no matching lines → stop silently.

---

## Step 2: Show changed files and ask

List only the ELK-related changed files.

Ask:
> "Commit ELK config?
> {{list of changed files}}
> 1. Yes
> 2. No"

If No → stop.

---

## Step 3: Determine commit message

If changed files include `elk/`, `.env`, `Makefile`, or `ELK_README.md`:
  → `"chore(elk): add ELK stack config"`

If changed files include `kibana/*.ndjson` or `elk/demo-logs.sh`:
  → extract slug from ndjson filename
  → `"chore(elk): add kibana dashboard {{slug}}"`

If both sets changed:
  → `"chore(elk): add ELK stack config and dashboards"`

---

## Step 4: Commit

Run:
```bash
git add elk/ .env Makefile ELK_README.md kibana/ elk/demo-logs.sh 2>/dev/null; true
git commit -m "{{commit message}}"
```

Show the commit hash on success.

---

## Step 5: Ask about push

> "Push to remote?
> 1. Yes
> 2. No"

If No → stop.

If Yes:
Run: `git remote -v`
If no remote configured:
> "No remote configured. Skipping push."
Stop.

Run: `git push origin HEAD`
On success: show the remote URL.
On failure: show the error output from git.
