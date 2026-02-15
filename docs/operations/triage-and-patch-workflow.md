# BidderSweet Command Center: Triage & Patch Workflow

This document outlines the standard operating procedure for triaging a production error, proposing a patch, and verifying the fix.

## 1. Triage Production Error

**Goal:** Understand the error and its impact.

**Action:** Use `ops_triage_prod_error` with the `request_id` or other relevant filters from the alert.

```
ops_triage_prod_error(request_id='...', service='...', ...)
```

**Analysis:**
- Review the output for error messages, stack traces, and relevant log lines.
- Identify the affected service(s) and the approximate time of the error.
- Determine if the error is new or recurring.
- Form an initial hypothesis about the root cause (e.g., bad deploy, user input, upstream service failure).

## 2. Investigate Potential Causes

### 2.1. Check for Recent Deploys

If the triage report suggests the error might be related to a recent deployment:

**Action:** Run `ops_env_diff` to compare production and staging environments for the affected service.

```
ops_env_diff(service_a='<service-name>-prod', service_b='<service-name>-staging')
```

**Analysis:**
- Look for differences in environment variables, especially for feature flags, API keys, or service URLs.
- Note any unexpected changes that could explain the failure.

### 2.2. Locate Relevant Code

**Goal:** Pinpoint the code location related to the error.

**Action:** Use `repo_search` with terms from the error message or stack trace. For more targeted searches, use `repo_symbols`.

```
# Example using repo_search
repo_search(query='<error_message_snippet>')

# Example using repo_symbols to find a method definition
repo_symbols(query='<method_name_from_stacktrace>')
```

**Analysis:**
- Follow the code path to understand the logic.
- Identify the exact line(s) of code that are likely causing the error.

## 3. Propose a Patch

**Goal:** Create a minimal, targeted fix for the identified issue.

**Action:** Based on the code analysis, formulate a patch. Use `repo_propose_patch` to generate a diff. **DO NOT APPLY THE PATCH.**

```
# First, read the file to get context
repo_read_file(path='path/to/file.rb')

# Then, propose the patch
repo_propose_patch(
  path='path/to/file.rb',
  ...
)
```

**User Confirmation Required:**
> **[AI to User]** I have identified a potential root cause in `path/to/file.rb` and prepared a patch.
>
> **Hypothesis:** ...
> **Patch Summary:** ...
>
> ```diff
> --- a/path/to/file.rb
> +++ b/path/to/file.rb
> ...
> ```
>
> **Do you want to APPLY this patch?**

## 4. Verify the Fix (Locally)

**Goal:** Ensure the patch fixes the issue and doesn't introduce regressions.

**Action (after user approval):**
1.  Apply the patch using `repo_apply_patch`.
2.  Run the fullstack smoke suite to test critical user flows.

```
# Apply the patch
repo_apply_patch(...)

# Run smoke tests
dev_smoke_fullstack(serviceName='biddersweet-backend') # Or relevant service
```

**Analysis:**
- Confirm that all smoke tests pass.
- If tests fail, analyze the output and revise the patch.

## 5. Verify the Fix (Post-Deployment)

**Goal:** Confirm the fix is working in production and the error has subsided. This step is to be performed after the change is deployed.

**Action:**
1.  Monitor logs for the affected service, filtering for the specific error.
2.  Check metrics to see if error rates have decreased and if system performance is nominal.

```
# Example: Check logs for error messages
list_logs(resource=['<service-id>'], text=['<error_message>'], level=['error'])

# Example: Check metrics for error rate and latency
get_metrics(resourceId='<service-id>', metricTypes=['http_request_count', 'http_latency'], aggregateHttpRequestCountsBy='statusCode')
```

**Analysis:**
- Confirm that the error is no longer appearing in the logs.
- Verify that the 5xx status code count has returned to baseline.
- Ensure that latency and other key performance indicators are healthy.

## 6. Final Report

**Goal:** Document the incident for future reference.

- **Root Cause Hypothesis:** A brief explanation of what went wrong.
- **Patch Summary:** A description of the changes made.
- **Verification Signals:** Links to or summaries of the logs and metrics that confirm the fix.
