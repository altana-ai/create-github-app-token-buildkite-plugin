# Create GitHub App Token Buildkite Plugin

A [Buildkite plugin](https://buildkite.com/docs/agent/v3/plugins) that creates GitHub App installation access tokens for authenticating with GitHub APIs in your Buildkite pipelines.

This plugin is inspired by and provides similar functionality to the [actions/create-github-app-token](https://github.com/actions/create-github-app-token) GitHub Action.

## Example

Generate a GitHub App token and use it to authenticate with GitHub:

```yaml
steps:
  - label: "Generate GitHub App Token"
    plugins:
      - altana-ai/create-github-app-token#v0.6.0:
          app-id: "$$GITHUB_APP_ID"
          private-key: "$$GITHUB_APP_PRIVATE_KEY"
    command: |
      # Token is now available in GITHUB_TOKEN environment variable
      curl -H "Authorization: Bearer \$GITHUB_TOKEN" https://api.github.com/user
```

## Configuration

### Required

#### `app-id` (string)

The GitHub App ID or a reference to an environment variable containing the App ID. You can find the App ID in your GitHub App's settings page.

- **Direct value**: `"123456"`
- **Environment variable reference**: `"$$GITHUB_APP_ID"` (recommended for security)

> **Note**: Use `$$` to prevent Buildkite from interpolating the variable. The plugin will handle the environment variable expansion internally.

#### `private-key` (string)

The GitHub App's private key in PEM format or a reference to an environment variable containing the private key. This should be stored securely using Buildkite secrets.

- **Environment variable reference**: `"$$GITHUB_APP_PRIVATE_KEY"` (recommended)
- **Direct value**: Not recommended for security reasons

> **Note**: Use `$$` to prevent Buildkite from interpolating the variable. The plugin will handle the environment variable expansion internally.

### Optional

#### `owner` (string)

Repository owner. If not specified, defaults to the current repository owner extracted from `BUILDKITE_REPO`.

Example: `"octocat"`

#### `repositories` (string)

Comma or newline-separated list of repository names to scope the token access. If not specified, the token will have access to all repositories the GitHub App is installed on.

Example: `"repo1,repo2"` or:

```yaml
repositories: |
  repo1
  repo2
```

#### `skip-token-revoke` (string)

Skip automatic token revocation during cleanup. Set to `"true"` to skip revocation.

Default: `"false"`

#### `github-api-url` (string)

GitHub REST API URL. Useful for GitHub Enterprise Server instances.

Default: `"https://api.github.com"`

Example: `"https://github.example.com/api/v3"`

#### `output-variable` (string)

The name of the environment variable to store the generated token. This is a Buildkite-specific parameter.

Default: `GITHUB_TOKEN`

Example: `"CUSTOM_TOKEN_VAR"`

#### `max-attempts` (integer)

How many times each GitHub API request is attempted before the step fails. Only
transient failures are retried; see [Retries](#retries).

Default: `5`

#### `max-retry-wait` (integer)

The most seconds one request may spend waiting between attempts. A retry that
would take the total past this limit, such as a long `Retry-After`, fails the
step instead.

Default: `60`

### Permission parameters

Each `permission-*` option sets one permission on the minted token, to `read` or
`write` (a few, such as `permission-workflows`, only accept `write`). The option
name maps to the API permission of the same name with dashes replaced by
underscores, so `permission-pull-requests` requests `pull_requests`.

The list mirrors the inputs of
[`actions/create-github-app-token`](https://github.com/actions/create-github-app-token),
which generates it from GitHub's OpenAPI description of the
[create installation access token](https://docs.github.com/en/rest/apps/apps#create-an-installation-access-token-for-an-app)
endpoint.

When no `permission-*` option is set, the token inherits every permission the app
installation has. Setting even one narrows the token to exactly what you list, so
list everything the step needs.

> [!IMPORTANT]
> `permission-actions` and `permission-workflows` are different permissions.
> `actions` covers workflow runs and artifacts; `workflows` is what lets a token
> **create or update files under `.github/workflows/`**. A bot that opens pull
> requests touching workflow files — Renovate, for instance — needs
> `permission-workflows: write`, and GitHub rejects the push with a
> `refusing to allow a GitHub App to create or update workflow` error without it.

#### Repository permissions

- `permission-actions`
- `permission-administration`
- `permission-artifact-metadata`
- `permission-attestations`
- `permission-checks`
- `permission-codespaces`
- `permission-contents`
- `permission-dependabot-secrets`
- `permission-deployments`
- `permission-discussions`
- `permission-environments`
- `permission-issues`
- `permission-merge-queues`
- `permission-metadata`
- `permission-packages`
- `permission-pages`
- `permission-pull-requests`
- `permission-repository-custom-properties`
- `permission-repository-hooks`
- `permission-repository-projects`
- `permission-secret-scanning-alerts`
- `permission-secrets`
- `permission-security-events`
- `permission-single-file`
- `permission-statuses`
- `permission-vulnerability-alerts`
- `permission-workflows`

#### Organization and user permissions

- `permission-custom-properties-for-organizations`
- `permission-email-addresses`
- `permission-enterprise-custom-properties-for-organizations`
- `permission-followers`
- `permission-git-ssh-keys`
- `permission-gpg-keys`
- `permission-interaction-limits`
- `permission-members`
- `permission-organization-administration`
- `permission-organization-announcement-banners`
- `permission-organization-copilot-seat-management`
- `permission-organization-custom-org-roles`
- `permission-organization-custom-properties`
- `permission-organization-custom-roles`
- `permission-organization-events`
- `permission-organization-hooks`
- `permission-organization-packages`
- `permission-organization-personal-access-token-requests`
- `permission-organization-personal-access-tokens`
- `permission-organization-plan`
- `permission-organization-projects`
- `permission-organization-secrets`
- `permission-organization-self-hosted-runners`
- `permission-organization-user-blocking`
- `permission-profile`
- `permission-starring`
- `permission-team-discussions`

#### Deprecated

- `permission-organization-members` — this plugin's original name for
  `permission-members`. Still honoured, and still mapped to the `members` API
  permission, but it logs a warning; prefer `permission-members`.

## Usage Examples

### Basic Usage

```yaml
steps:
  - label: "Use GitHub App Token"
    plugins:
      - altana-ai/create-github-app-token#v0.6.0:
          app-id: "$$GITHUB_APP_ID"
          private-key: "$$GITHUB_APP_PRIVATE_KEY"
    command: |
      # Use the token to make authenticated requests
      gh api user
```

### With Permissions and Repository Scope

```yaml
steps:
  - label: "Scoped GitHub App Token"
    plugins:
      - altana-ai/create-github-app-token#v0.6.0:
          app-id: "$$GITHUB_APP_ID"
          private-key: "$$GITHUB_APP_PRIVATE_KEY"
          repositories: "repo1,repo2"
          permission-contents: "read"
          permission-issues: "write"
          permission-pull-requests: "write"
    command: |
      # Token has limited scope and permissions
      gh api repos/owner/repo1/contents/README.md
```

### With Organization Members Permission

```yaml
steps:
  - label: "Organization Members Access"
    plugins:
      - altana-ai/create-github-app-token#v0.6.0:
          app-id: "$$GITHUB_APP_ID"
          private-key: "$$GITHUB_APP_PRIVATE_KEY"
          permission-members: "read"
    command: |
      # Token can access organization member information
      gh api orgs/myorg/members
```

### For a Bot That Updates Workflow Files

Editing `.github/workflows/**` needs `permission-workflows`, which is separate
from `permission-actions`:

```yaml
steps:
  - label: ":robot_face: renovate"
    plugins:
      - altana-ai/create-github-app-token#v0.6.0:
          app-id: "$$RENOVATE_APP_ID"
          private-key: "$$RENOVATE_APP_PRIVATE_KEY"
          permission-contents: "write"
          permission-pull-requests: "write"
          permission-issues: "write"
          permission-workflows: "write"
      - altana-ai/renovate#v0.1.1: ~
```

### GitHub Enterprise Server

```yaml
steps:
  - label: "Enterprise GitHub App Token"
    plugins:
      - altana-ai/create-github-app-token#v0.6.0:
          app-id: "$$GITHUB_APP_ID"
          private-key: "$$GITHUB_APP_PRIVATE_KEY"
          github-api-url: "https://github.company.com/api/v3"
    command: |
      # Works with GitHub Enterprise Server
      gh api user
```

### Skip Token Revocation

```yaml
steps:
  - label: "Long-lived Token"
    plugins:
      - altana-ai/create-github-app-token#v0.6.0:
          app-id: "$$GITHUB_APP_ID"
          private-key: "$$GITHUB_APP_PRIVATE_KEY"
          skip-token-revoke: "true"
    command: |
      # Token won't be revoked automatically
      echo "Token will remain active until expiration"
```

### Custom Output Variable

```yaml
steps:
  - label: "Custom Token Variable"
    plugins:
      - altana-ai/create-github-app-token#v0.6.0:
          app-id: "$$GITHUB_APP_ID"
          private-key: "$$GITHUB_APP_PRIVATE_KEY"
          output-variable: "MY_GITHUB_TOKEN"
    command: |
      # Token is available in MY_GITHUB_TOKEN
      curl -H "Authorization: Bearer \$MY_GITHUB_TOKEN" https://api.github.com/repos/owner/repo
```

### Using Buildkite Secrets (Recommended)

Map [Buildkite secrets](https://buildkite.com/docs/pipelines/security/secrets/buildkite-secrets)
to the environment variables this plugin reads with the `secrets` step attribute.
It needs agent 3.106.0 or later, secrets are scoped to the agent's cluster, and
their values are redacted from build logs automatically:

```yaml
steps:
  - label: "Generate Token with Secrets"
    secrets:
      GITHUB_APP_ID: my_github_app_id
      GITHUB_APP_PRIVATE_KEY: my_github_app_private_key
    plugins:
      - altana-ai/create-github-app-token#v0.6.0:
          app-id: "$$GITHUB_APP_ID"
          private-key: "$$GITHUB_APP_PRIVATE_KEY"
    command: |
      gh api user
```

The `$$` stops Buildkite interpolating the variable when the pipeline is
uploaded, so the plugin resolves it on the agent, where the secret exists.

### Restricting Who Can Read the Private Key

The private key is long-lived, and anything that can read it can mint tokens for
every repository the app is installed on. A Buildkite secret is readable by every
agent in its cluster by default, so attach an
[access policy](https://buildkite.com/docs/pipelines/security/secrets/buildkite-secrets/access-policies)
to it — the cluster's secret → **Access** tab → *Restrict access to agents
matching a policy*:

```yaml
# Only this pipeline, and only when Buildkite itself started the build.
- pipeline_id:
    - "01234567-89ab-cdef-0123-456789abcdef"
  build_source:
    - "schedule"
    - "ui"
```

Claims within a rule are ANDed, values within a claim are ORed, rules are ORed,
and access is denied when nothing matches. Prefer the first-party claims
(`pipeline_id`, `build_source`, `cluster_queue_id`), which Buildkite generates;
the third-party ones (`pipeline_slug`, `build_branch`, `build_creator`) are
convenient but derive from user- or tool-supplied values, so they make a weaker
boundary.

Restricting `build_source` is what stops a pull request against the pipeline's own
repository from reading the key — an untrusted branch cannot mint a token even if
it rewrites the pipeline.

## Security Features

- **Token Redaction**: The generated token is automatically added to Buildkite's CLI redactor to prevent accidental logging
- **Automatic Token Revocation**: Tokens are automatically revoked after command execution (unless `skip-token-revoke` is set to `true`)
- **Environment Cleanup**: Tokens are removed from the environment after command execution
- **Temporary Key Storage**: Private keys are stored in temporary files that are immediately cleaned up
- **Scoped Permissions**: Use permission parameters to limit token access to only what's needed
- **Repository Scoping**: Use the `repositories` parameter to limit token access to specific repositories

## How It Works

1. **Environment Variable Expansion**: Resolves environment variable references (e.g., `$GITHUB_APP_ID`) to their actual values
2. **JWT Generation**: Creates a JSON Web Token (JWT) using your GitHub App ID and private key
3. **Installation Discovery**: Finds the GitHub App installation for the current repository
4. **Token Generation**: Uses the JWT to request an installation access token from GitHub's API
5. **Security Setup**: Adds the token to Buildkite's redactor and exports it as an environment variable
6. **Cleanup**: Removes the token from the environment after command execution

### Retries

The installation lookup and the token request each retry transient failures:

- curl transport errors: connection refused or reset, DNS, TLS, timeouts
- HTTP 429 and 5xx
- HTTP 403 when it is a rate limit (a `Retry-After` header, or
  `x-ratelimit-remaining: 0`)

The wait before the next attempt is the server's `Retry-After`, else the time
until `x-ratelimit-reset` when the rate limit is exhausted, else exponential
backoff with jitter: 2-3s, 4-7s, 8-15s, 16-31s. With the defaults the worst case
is about a minute of waiting. Every request has a 10s connect timeout and a 30s
overall timeout, and signs a fresh JWT, so a retry never sends an expired one.

Anything else, such as 401, 404 or 422, fails at once. Each failed attempt logs
its attempt number, the HTTP status or curl exit code, and the response body;
neither the JWT nor the minted token is logged.

### Environment Variable Expansion

The plugin supports referencing environment variables using the `$VARIABLE_NAME` syntax for the `app-id` and `private-key` parameters. This allows you to keep sensitive values out of your pipeline configuration:

```yaml
# In your pipeline YAML (secure - no secrets in config)
app-id: "$$GITHUB_APP_ID"
private-key: "$$GITHUB_APP_PRIVATE_KEY"
```

The plugin will automatically expand `$GITHUB_APP_ID` to the value of the `GITHUB_APP_ID` environment variable. Use the double-dollar (`$$`) syntax in Buildkite to prevent Buildkite from interpolating the variables before the plugin receives them.

## Requirements

- `openssl` - Used for JWT signature generation
- `curl` - Used for GitHub API requests
- `jq` - Used for JSON parsing
- `buildkite-agent` - Required for token redaction
- Repository must have the GitHub App installed

## Troubleshooting

### Error: Unable to parse repository from BUILDKITE_REPO

This error occurs when the plugin cannot determine the GitHub repository from the `BUILDKITE_REPO` environment variable. Ensure your repository URL is in one of these formats:

- `git@github.com:owner/repo.git`
- `https://github.com/owner/repo.git`

### Error: GitHub App is not installed

If you see the error "GitHub App is not installed on owner/repository", the plugin has detected that your GitHub App is not installed on the target repository or organization. Follow the provided instructions:

1. Go to your GitHub App settings
2. Click 'Install App' in the left sidebar
3. Select the organization/account
4. Choose to install on selected repositories or all repositories

This error replaces the generic "Failed to get installation ID" message and provides clear next steps.

### Error: Failed to generate installation token

The message names the HTTP status, or `HTTP 000` when no response arrived; the
attempt log above it shows each failure. A transient failure that outlasted the
retries reads `still failing after N attempts`. Otherwise this typically
indicates:

1. Invalid private key format
2. Clock skew (JWT timestamps are invalid)
3. Insufficient GitHub App permissions

## Development

To contribute to this plugin:

1. Clone the repository
2. Make your changes
3. Run the tests (below) and, for agent-side behaviour, a Buildkite pipeline
4. Submit a pull request

### Tests

The hooks are covered by [bats](https://github.com/bats-core/bats-core) tests
that stub `curl` and `buildkite-agent`, so they never reach the GitHub API:

```bash
bats tests
```

`tests/revocation.bats` drives `pre-command` and `post-command` the way
`buildkite-agent` does — the hook body is sourced, then the next hook runs as a
child process — because only *exported* variables survive that boundary. Any
hand-off between the two hooks has to be tested through it to be meaningful.

`shellcheck hooks/* tests/test_helper.bash tests/stubs/*` must also be clean.
Both run in CI on every pull request.
