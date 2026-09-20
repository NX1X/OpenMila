#!/usr/bin/env bash
# Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
#
# Applies OpenMila's branch and tag rulesets with the GitHub CLI. Run it as the
# repository owner; it changes settings, so it is never run by CI.
#
#   scripts/port/apply-repo-rules.sh [owner/repo]
#
# Afterwards, in the web interface: Actions policy (allowlist plus
# "require actions pinned to a full-length commit SHA"), secret scanning with
# push protection, private vulnerability reporting, Dependabot alerts on with
# version updates off, and Discussions on. See docs/port/GO-PUBLIC.md.
set -euo pipefail
REPO="${1:-NX1X/OpenMila}"

echo "==> branch ruleset on main"
gh api "repos/$REPO/rulesets" --method POST --input - <<'JSON'
{
  "name": "main",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["refs/heads/main"], "exclude": [] } },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "required_linear_history" },
    { "type": "required_signatures" },
    { "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 1,
        "dismiss_stale_reviews_on_push": true,
        "require_code_owner_review": true,
        "require_last_push_approval": false,
        "required_review_thread_resolution": true,
        "allowed_merge_methods": ["merge", "squash"]
      } },
    { "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": true,
        "required_status_checks": [{ "context": "linux" }]
      } }
  ]
}
JSON

echo "==> tag ruleset on v*"
gh api "repos/$REPO/rulesets" --method POST --input - <<'JSON'
{
  "name": "release tags",
  "target": "tag",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["refs/tags/v*"], "exclude": [] } },
  "rules": [
    { "type": "deletion" },
    { "type": "update" },
    { "type": "non_fast_forward" }
  ]
}
JSON

echo "==> rulesets now on $REPO"
gh api "repos/$REPO/rulesets" --jq '.[] | "\(.id) \(.name) \(.target) \(.enforcement)"'
