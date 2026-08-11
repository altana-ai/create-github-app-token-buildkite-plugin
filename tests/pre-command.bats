#!/usr/bin/env bats

load 'test_helper'

setup_file() {
  load 'test_helper'
  generate_test_key
}

setup() {
  setup_test_env
}

teardown() {
  teardown_test_env
}

# The variables the hook leaves behind for post-command, as buildkite-agent sees
# them: `export -p` lists exported variables only, so a plain assignment is
# invisible here — which is the whole point.
exported_env() {
  bash -c 'source "$PRE_COMMAND" >/dev/null 2>&1; export -p'
}

@test "exports the token as GITHUB_TOKEN by default" {
  run exported_env

  [ "$status" -eq 0 ]
  [[ "$output" == *'GITHUB_TOKEN="ghs_stubaccesstoken"'* ]]
}

@test "exports the token as the configured output-variable" {
  export BUILDKITE_PLUGIN_CREATE_GITHUB_APP_TOKEN_OUTPUT_VARIABLE="MY_GITHUB_TOKEN"

  run exported_env

  [ "$status" -eq 0 ]
  [[ "$output" == *'MY_GITHUB_TOKEN="ghs_stubaccesstoken"'* ]]
}

@test "exports the installation id" {
  run exported_env

  [ "$status" -eq 0 ]
  [[ "$output" == *'GITHUB_APP_INSTALLATION_ID="87654321"'* ]]
}

@test "exports the revocation hand-off variables" {
  run exported_env

  [ "$status" -eq 0 ]
  [[ "$output" == *'GITHUB_APP_TOKEN_FOR_REVOCATION="ghs_stubaccesstoken"'* ]]
  [[ "$output" == *'GITHUB_API_URL_FOR_REVOCATION="https://api.github.com"'* ]]
}

@test "exports the configured api url for revocation" {
  export BUILDKITE_PLUGIN_CREATE_GITHUB_APP_TOKEN_GITHUB_API_URL="https://github.example.com/api/v3"

  run exported_env

  [ "$status" -eq 0 ]
  [[ "$output" == *'GITHUB_API_URL_FOR_REVOCATION="https://github.example.com/api/v3"'* ]]
}

@test "leaves the revocation variables unset when skip-token-revoke is true" {
  export BUILDKITE_PLUGIN_CREATE_GITHUB_APP_TOKEN_SKIP_TOKEN_REVOKE="true"

  run exported_env

  [ "$status" -eq 0 ]
  [[ "$output" != *"GITHUB_APP_TOKEN_FOR_REVOCATION"* ]]
  [[ "$output" != *"GITHUB_API_URL_FOR_REVOCATION"* ]]
}

@test "registers the token with the agent redactor" {
  run bash "$PRE_COMMAND"

  [ "$status" -eq 0 ]
  run cat "$REDACTOR_LOG"
  [[ "$output" == *"redactor add"* ]]
}

@test "expands app-id and private-key from environment variables" {
  export TEST_APP_ID="999999"
  export BUILDKITE_PLUGIN_CREATE_GITHUB_APP_TOKEN_APP_ID='$TEST_APP_ID'

  run bash "$PRE_COMMAND"

  [ "$status" -eq 0 ]
  run curl_calls
  [[ "$output" == *"/repos/test-owner/test-repo/installation"* ]]
}

@test "requests the configured permissions" {
  export BUILDKITE_PLUGIN_CREATE_GITHUB_APP_TOKEN_PERMISSION_CONTENTS="read"
  export BUILDKITE_PLUGIN_CREATE_GITHUB_APP_TOKEN_PERMISSION_PULL_REQUESTS="write"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 0 ]
  [ "$(token_request_body | jq -r '.permissions.contents')" = "read" ]
  [ "$(token_request_body | jq -r '.permissions.pull_requests')" = "write" ]
}

# Renovate — and anything else that edits .github/workflows — needs `workflows`,
# which is a different app permission from `actions` (workflow runs and
# artifacts). Both are requestable.
@test "requests the workflows permission, which editing workflow files needs" {
  export BUILDKITE_PLUGIN_CREATE_GITHUB_APP_TOKEN_PERMISSION_WORKFLOWS="write"
  export BUILDKITE_PLUGIN_CREATE_GITHUB_APP_TOKEN_PERMISSION_ACTIONS="read"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 0 ]
  [ "$(token_request_body | jq -r '.permissions.workflows')" = "write" ]
  [ "$(token_request_body | jq -r '.permissions.actions')" = "read" ]
}

@test "requests permissions beyond the repository-scoped ones" {
  export BUILDKITE_PLUGIN_CREATE_GITHUB_APP_TOKEN_PERMISSION_MEMBERS="read"
  export BUILDKITE_PLUGIN_CREATE_GITHUB_APP_TOKEN_PERMISSION_ORGANIZATION_PROJECTS="write"
  export BUILDKITE_PLUGIN_CREATE_GITHUB_APP_TOKEN_PERMISSION_SECRET_SCANNING_ALERTS="read"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 0 ]
  [ "$(token_request_body | jq -r '.permissions.members')" = "read" ]
  [ "$(token_request_body | jq -r '.permissions.organization_projects')" = "write" ]
  [ "$(token_request_body | jq -r '.permissions.secret_scanning_alerts')" = "read" ]
}

@test "still honours the deprecated permission-organization-members" {
  export BUILDKITE_PLUGIN_CREATE_GITHUB_APP_TOKEN_PERMISSION_ORGANIZATION_MEMBERS="read"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 0 ]
  # The API permission has always been `members`; the old option name must not
  # reach GitHub as `organization_members`, which it would reject.
  [ "$(token_request_body | jq -r '.permissions.members')" = "read" ]
  [ "$(token_request_body | jq -r '.permissions | has("organization_members")')" = "false" ]
  [[ "$output" == *"deprecated"* ]]
}

@test "omits permissions entirely when none are configured" {
  run bash "$PRE_COMMAND"

  [ "$status" -eq 0 ]
  # An absent `permissions` key makes the token inherit the installation's
  # permissions; an empty object would grant nothing.
  [ "$(token_request_body | jq -r 'has("permissions")')" = "false" ]
}

@test "scopes the token to a comma-separated repository list" {
  export BUILDKITE_PLUGIN_CREATE_GITHUB_APP_TOKEN_REPOSITORIES="repo1, repo2"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 0 ]
  [ "$(token_request_body | jq -c '.repositories')" = '["repo1","repo2"]' ]
}

@test "scopes the token to a newline-separated repository list" {
  export BUILDKITE_PLUGIN_CREATE_GITHUB_APP_TOKEN_REPOSITORIES="repo1
repo2
repo3"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 0 ]
  # The YAML block-scalar form the README documents: every entry has to survive,
  # not just the first line.
  [ "$(token_request_body | jq -c '.repositories')" = '["repo1","repo2","repo3"]' ]
}

@test "omits repositories when none are configured" {
  run bash "$PRE_COMMAND"

  [ "$status" -eq 0 ]
  [ "$(token_request_body | jq -r 'has("repositories")')" = "false" ]
}

@test "fails when app-id is missing" {
  unset BUILDKITE_PLUGIN_CREATE_GITHUB_APP_TOKEN_APP_ID

  run bash "$PRE_COMMAND"

  [ "$status" -eq 1 ]
  [[ "$output" == *"app-id is required"* ]]
}

@test "fails when private-key is missing" {
  unset BUILDKITE_PLUGIN_CREATE_GITHUB_APP_TOKEN_PRIVATE_KEY

  run bash "$PRE_COMMAND"

  [ "$status" -eq 1 ]
  [[ "$output" == *"private-key is required"* ]]
}

@test "fails with install instructions when the app is not installed" {
  export STUB_INSTALLATION_HTTP_CODE="404"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 1 ]
  [[ "$output" == *"GitHub App is not installed on test-owner/test-repo"* ]]
}

@test "fails when the token request returns no token" {
  export STUB_ACCESS_TOKEN=""

  run bash "$PRE_COMMAND"

  [ "$status" -eq 1 ]
  [[ "$output" == *"Failed to generate installation token"* ]]
}
