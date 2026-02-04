# Case Study: GitHub Actions Not Running on PRs with Merge Conflicts

## Issue Reference
- **Issue**: [#459](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/459)
- **Title**: fix раньше github actins отрабатывали даже при конфликте веток (GitHub Actions used to work even with branch conflicts)
- **Reporter**: Jhon-Crow
- **Date**: 2026-02-04

## Problem Statement

The repository owner reported that GitHub Actions workflows previously ran even when pull request branches had merge conflicts with the main branch. This allowed checking build status and architecture validation regardless of merge conflict state. The behavior changed and now workflows do not run when conflicts exist.

## Root Cause Analysis

### Technical Background

GitHub Actions workflows triggered by the `pull_request` event rely on a special merge reference (`refs/pull/:prNumber/merge`). This reference is a hypothetical merge commit that GitHub creates to simulate what the code would look like after merging.

**When merge conflicts exist, GitHub cannot create this merge reference**, and as a result:
1. The `pull_request` event cannot determine the merged code state
2. The workflow simply does not trigger
3. No error message is displayed to the user

### Why It May Have "Worked Before"

Several possibilities:
1. **Branch was never actually in conflict before** - The user may not have encountered true merge conflicts previously
2. **Different trigger type was used** - Some workflows might have used `push` instead of `pull_request`
3. **GitHub behavior change** - GitHub's handling of conflicting PRs may have changed over time
4. **Perception vs reality** - The CI might have run on a previous commit before conflicts arose

### Current Workflow Configuration

All workflows in `.github/workflows/` use this trigger pattern:
```yaml
on:
  push:
    branches: [ main, issue-* ]
  pull_request:
    branches: [ main ]
```

This means:
- **Push events**: Run on `main` and `issue-*` branches (direct pushes)
- **Pull request events**: Run on PRs targeting `main` branch

The `push` trigger should still work for direct pushes to `issue-*` branches, but `pull_request` won't trigger if there are merge conflicts.

## Solution

### Option 1: Use `pull_request_target` Event (Recommended with Caveats)

Replace `pull_request` with `pull_request_target`:

```yaml
on:
  push:
    branches: [ main, issue-* ]
  pull_request_target:
    branches: [ main ]
```

**Security Warning**: `pull_request_target` runs in the context of the base branch with access to secrets. It should only be used for:
- Read-only checks (architecture validation, linting)
- Workflows that don't execute PR code
- Trusted contributors

**Safe pattern**: Explicitly checkout the PR head with limited permissions:
```yaml
- uses: actions/checkout@v4
  with:
    ref: ${{ github.event.pull_request.head.sha }}
```

### Option 2: Hybrid Approach

Use both triggers:
```yaml
on:
  push:
    branches: [ main, issue-* ]
  pull_request:
    branches: [ main ]
  pull_request_target:
    branches: [ main ]
    types: [opened, synchronize, reopened]
```

With job condition to avoid duplicate runs:
```yaml
jobs:
  build:
    if: |
      github.event_name == 'push' ||
      github.event_name == 'pull_request' ||
      (github.event_name == 'pull_request_target' && github.event.pull_request.mergeable == false)
```

### Option 3: Manual Workflow Dispatch

Add `workflow_dispatch` to allow manual triggering when CI doesn't run:
```yaml
on:
  push:
    branches: [ main, issue-* ]
  pull_request:
    branches: [ main ]
  workflow_dispatch:
```

This is already present in the current workflows.

## Implemented Solution

We chose **Option 1** with security safeguards for workflows that are safe to run with `pull_request_target`:

1. **Safe workflows** (no code execution from PR): Architecture check, Interop check
2. **Needs careful handling**: Build, C# validation (runs dotnet build)
3. **Test workflows**: Require code execution, need special handling

For the build workflow, we use explicit checkout of PR head to ensure we test the actual PR code:
```yaml
- uses: actions/checkout@v4
  with:
    ref: ${{ github.event.pull_request.head.sha }}
```

## References

- [GitHub Community Discussion #26304: Run actions on Pull Requests with merge conflicts](https://github.com/orgs/community/discussions/26304)
- [GitHub Community Discussion #11265: Show an explanation for why Actions workflows aren't run on PRs when there is a merge conflict](https://github.com/orgs/community/discussions/11265)
- [GitHub Community Discussion #46022: Why the workflow does or doesn't run on `pull_request` event?](https://github.com/orgs/community/discussions/46022)
- [Medium Article: GitHub Actions and Merge Conflicts: A Comprehensive Analysis](https://medium.com/@FartsyRainbowOctopus/github-actions-and-merge-conflicts-a-comprehensive-analysis-and-definitive-guide-to-unlocking-54fa45a38886)

## Timeline

| Date | Event |
|------|-------|
| 2026-02-04 | Issue #459 reported |
| 2026-02-04 | Root cause identified as `pull_request` event limitation |
| 2026-02-04 | Solution implemented using `pull_request_target` with security safeguards |

## Lessons Learned

1. **GitHub Actions `pull_request` event has a known limitation** - It cannot run when merge conflicts exist
2. **No notification is provided** - Users are not informed why workflows didn't trigger
3. **`pull_request_target` is a workaround but has security implications** - Must be used carefully
4. **The `push` trigger is unaffected** - Direct pushes to branches still trigger workflows
5. **Documentation and community awareness** - This issue has been discussed for years without official resolution
