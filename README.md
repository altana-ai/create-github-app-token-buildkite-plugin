# Create GitHub App Token Buildkite Plugin

A [Buildkite plugin](https://buildkite.com/docs/agent/v3/plugins) that creates GitHub App installation access tokens for authenticating with GitHub APIs in your Buildkite pipelines.

This plugin is inspired by and provides similar functionality to the [actions/create-github-app-token](https://github.com/actions/create-github-app-token) GitHub Action.

## Example

Generate a GitHub App token and use it to authenticate with GitHub:

```yaml
steps:
  - label: "Generate GitHub App Token"
    plugins:
      - jasonwbarnett/create-github-app-token#main:
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

### Permission Parameters

You can specify granular permissions for the generated token. Each permission can be set to `"read"` or `"write"`.

#### `permission-actions` (string)
Actions workflows permission level.

#### `permission-administration` (string)
Repository administration permission level.

#### `permission-checks` (string)
Code checks permission level.

#### `permission-codespaces` (string)
Codespaces management permission level.

#### `permission-contents` (string)
Repository contents permission level.

#### `permission-deployments` (string)
Deployments permission level.

#### `permission-environments` (string)
Environments permission level.

#### `permission-issues` (string)
Issues permission level.

#### `permission-metadata` (string)
Repository metadata permission level.

#### `permission-packages` (string)
Packages permission level.

#### `permission-pages` (string)
GitHub Pages permission level.

#### `permission-pull-requests` (string)
Pull requests permission level.

#### `permission-repository-hooks` (string)
Repository webhooks permission level.

#### `permission-repository-projects` (string)
Repository projects permission level.

#### `permission-security-events` (string)
Security events permission level.

#### `permission-statuses` (string)
Commit statuses permission level.

#### `permission-vulnerability-alerts` (string)
Vulnerability alerts permission level.

## Usage Examples

### Basic Usage

```yaml
steps:
  - label: "Use GitHub App Token"
    plugins:
      - jasonwbarnett/create-github-app-token#main:
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
      - jasonwbarnett/create-github-app-token#main:
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

### GitHub Enterprise Server

```yaml
steps:
  - label: "Enterprise GitHub App Token"
    plugins:
      - jasonwbarnett/create-github-app-token#main:
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
      - jasonwbarnett/create-github-app-token#main:
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
      - jasonwbarnett/create-github-app-token#main:
          app-id: "$$GITHUB_APP_ID"
          private-key: "$$GITHUB_APP_PRIVATE_KEY"
          output-variable: "MY_GITHUB_TOKEN"
    command: |
      # Token is available in MY_GITHUB_TOKEN
      curl -H "Authorization: Bearer \$MY_GITHUB_TOKEN" https://api.github.com/repos/owner/repo
```

### Using Buildkite Secrets (Recommended)

Create a `.buildkite/hooks/pre-command` script to securely retrieve secrets:

```bash
#!/bin/bash
export GITHUB_APP_ID=$(buildkite-agent secret get GITHUB_APP_ID)
export GITHUB_APP_PRIVATE_KEY=$(buildkite-agent secret get GITHUB_APP_PRIVATE_KEY)
```

Then reference them in your pipeline:

```yaml
steps:
  - label: "Generate Token with Secrets"
    plugins:
      - jasonwbarnett/create-github-app-token#main:
          app-id: "$$GITHUB_APP_ID"
          private-key: "$$GITHUB_APP_PRIVATE_KEY"
    command: |
      echo "Token generated securely using Buildkite secrets"
```

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

This typically indicates:
1. Invalid private key format
2. Clock skew (JWT timestamps are invalid)
3. Insufficient GitHub App permissions

## Development

To contribute to this plugin:

1. Clone the repository
2. Make your changes
3. Test with a Buildkite pipeline
4. Submit a pull request

## License

MIT (see [LICENSE](LICENSE))
