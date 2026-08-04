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
  [[ "$output" == *'"contents": "read"'* ]]
  [[ "$output" == *'"pull_requests": "write"'* ]]
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
