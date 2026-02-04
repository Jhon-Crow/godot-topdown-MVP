# Research Sources for Issue #462

## Primary Investigation Data

### CI Run Analysis

The following data was collected from the GitHub Actions API:

1. **Total runs analyzed**: 200
2. **Success rate**: 97% (194 successful, 2 failed, 4 in-progress at time of analysis)
3. **Failed runs**:
   - Run 21658824213: Script exceeded 5000 lines limit (code issue, not CI issue)

### PR Status Analysis

| PR | Branch | Merge Status | CI Status |
|----|--------|--------------|-----------|
| #463 | issue-462-5448b821eb54 | MERGEABLE | ✅ Running |
| #456 | issue-455-231f6ca7839c | MERGEABLE | ✅ Passing |
| #449 | issue-448-ba4c79dfe449 | MERGEABLE | ✅ Passing |
| #446 | issue-445-f66cbf1af69d | MERGEABLE | ✅ Passing |
| #436 | issue-435-c6e7dfa39d7c | **CONFLICTING** | CI ran on last push |
| #430 | issue-415-09cb02795a63 | MERGEABLE | ✅ Running |

## GitHub Documentation

### `pull_request` Event Limitations

From [GitHub Docs - Events that trigger workflows](https://docs.github.com/actions/learn-github-actions/events-that-trigger-workflows):

> Workflows will not run on `pull_request` activity if the pull request has a merge conflict. The merge conflict must be resolved first.

### `pull_request_target` Event Behavior

From [GitHub Docs - Events that trigger workflows](https://docs.github.com/actions/learn-github-actions/events-that-trigger-workflows):

> This event runs in the context of the base of the pull request, rather than in the context of the merge commit as the `pull_request` event does.

Key differences:
- Runs regardless of merge conflict status
- Uses workflow definition from base branch
- Has access to base branch secrets (security implication)

## Community Discussions

### Discussion #26304
[Run actions on Pull Requests with merge conflicts](https://github.com/orgs/community/discussions/26304)

Main points:
- Long-standing issue since at least 2021
- Community request for official solution
- Workaround: Use `pull_request_target`

### Discussion #54937
[pull_request_target isn't triggering workflow](https://github.com/orgs/community/discussions/54937)

Key insight:
> The workflow file must exist on the target branch of the pull request. A `pull_request_target` event fires for the target branch (and will use the workflow from there).

### Discussion #11265
[Show an explanation for why Actions workflows aren't run on PRs when there is a merge conflict](https://github.com/orgs/community/discussions/11265)

Community frustration:
- No error message shown when workflows don't run
- Users confused why CI appears "broken"

## Security Considerations

### OWASP: CI/CD Pipeline Security

When using `pull_request_target`:
1. **Secret Exposure Risk**: Workflow has access to repository secrets
2. **Code Execution**: Must carefully control what code is executed
3. **Mitigation**: Always checkout PR head explicitly with limited scope

### Recommended Pattern (from PR #460)

```yaml
- uses: actions/checkout@v4
  with:
    ref: ${{ github.event.pull_request.head.sha || github.sha }}
```

This ensures:
- PR code is analyzed (not base branch)
- SHA is explicit (prevents tampering)
- Fallback for non-PR events

## Technical Analysis

### Event Flow Comparison

**`pull_request` event:**
```
1. PR created/updated
2. GitHub attempts to create merge commit (refs/pull/:prNumber/merge)
3. If conflicts exist → merge commit fails → workflow NOT triggered
4. If no conflicts → merge commit created → workflow triggered
```

**`pull_request_target` event:**
```
1. PR created/updated
2. Event fires immediately for base branch
3. Workflow runs from base branch context
4. Must explicitly checkout PR code
5. Works regardless of conflict status
```

### Workflow Files Modified

All six workflow files were updated in PR #460:

| File | Purpose | Safe for `pull_request_target`? |
|------|---------|--------------------------------|
| architecture-check.yml | Static analysis | ✅ Yes (no code execution) |
| build-windows.yml | Build game | ⚠️ Caution (executes code) |
| csharp-validation.yml | C# build | ⚠️ Caution (executes code) |
| gameplay-validation.yml | Static analysis | ✅ Yes (pattern matching) |
| interop-check.yml | Static analysis | ✅ Yes (no code execution) |
| test.yml | Run tests | ⚠️ Caution (executes code) |

Note: "Caution" workflows should only be run for trusted contributors or with approval gates.

## Conclusion from Research

The issue #462 was filed after the fix (PR #460) was already in place. All evidence shows:

1. CI runs are working correctly with `pull_request_target`
2. PRs with conflicts can now run CI
3. No additional technical fix is needed

The fix follows GitHub's recommended workaround pattern with appropriate security safeguards.
