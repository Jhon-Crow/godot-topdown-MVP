# Research Sources for Issue #459

## Primary Sources

### GitHub Community Discussions

1. **Discussion #26304**: [Run actions on Pull Requests with merge conflicts](https://github.com/orgs/community/discussions/26304)
   - Main discussion about the limitation
   - Community requests for official solution

2. **Discussion #11265**: [Show an explanation for why Actions workflows aren't run on PRs when there is a merge conflict](https://github.com/orgs/community/discussions/11265)
   - Request for better error messaging
   - Explains the technical reason behind the limitation

3. **Discussion #46022**: [Why the workflow does or doesn't run on `pull_request` event?](https://github.com/orgs/community/discussions/46022)
   - Detailed explanation of event triggers
   - Workarounds discussed

4. **Discussion #50776**: [GitHub Actions: How to run jobs only if PR has no conflicts](https://github.com/orgs/community/discussions/50776)
   - Related discussion about conflict detection

## Technical Details

### The `pull_request` Event Mechanism

```
When pull_request event triggers:
1. GitHub attempts to create refs/pull/:prNumber/merge
2. This is a merge commit of PR head into base branch
3. Workflow runs against this merge commit
4. If merge conflicts exist → merge commit cannot be created → workflow does not run
```

### The `pull_request_target` Event Mechanism

```
When pull_request_target event triggers:
1. GitHub runs workflow from base branch (target)
2. No merge commit is required
3. Workflow runs regardless of conflict state
4. SECURITY: Workflow has access to base branch secrets
```

## Security Considerations

From GitHub documentation:
> The `pull_request_target` event runs in the context of the base of the pull request, rather than in the context of the merge commit. This means that secrets and write permissions are available to the workflow.

### Safe Use Cases for `pull_request_target`
- Labeling PRs
- Posting comments
- Running checks that don't execute PR code
- Architecture validation (checking file patterns, not executing code)

### Unsafe Use Cases
- Building/compiling PR code
- Running tests that execute PR code
- Any operation that runs code from an untrusted PR

### Mitigation Strategies
1. **Explicit checkout**: `ref: ${{ github.event.pull_request.head.sha }}`
2. **Limited permissions**: Use minimal required permissions
3. **Environment restrictions**: Use protected environments
4. **Approval required**: Require approval for first-time contributors

## Implementation Examples

### Safe Pattern for Read-Only Checks

```yaml
name: Architecture Check
on:
  push:
    branches: [ main, issue-* ]
  pull_request_target:
    branches: [ main ]

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ github.event.pull_request.head.sha || github.sha }}
      # Only run shell commands that analyze, don't execute code
```

### Pattern for Build Workflows (With Caution)

```yaml
name: Build
on:
  push:
    branches: [ main, issue-* ]
  pull_request_target:
    branches: [ main ]

permissions:
  contents: read  # Minimal permissions

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ github.event.pull_request.head.sha || github.sha }}
      # Build steps here
```

## Alternative Solutions Considered

### 1. Keep `pull_request` and Use `workflow_dispatch` for Manual Runs
- Pros: Most secure, no changes to existing behavior
- Cons: Requires manual intervention when conflicts exist

### 2. Use Both `pull_request` and `pull_request_target`
- Pros: Covers both scenarios
- Cons: Duplicate runs, complex conditions needed

### 3. Use Only `push` Trigger
- Pros: Always runs
- Cons: Doesn't run on PR events, loses PR-specific context

## Conclusion

The recommended solution is to use `pull_request_target` for workflows that don't execute untrusted code, with explicit checkout of the PR head commit. For build and test workflows, the security implications must be carefully considered.
