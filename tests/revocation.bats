#!/usr/bin/env bats
#
# End-to-end coverage for the revocation contract the README promises:
# "Tokens are automatically revoked after command execution (unless
# skip-token-revoke is set to true)".
#
# These tests drive both hooks across the same process boundary buildkite-agent
# puts between them — pre-command sourced, post-command spawned as a child — so
# they fail if the hand-off variables stop being exported.

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

@test "revokes the minted token after the command" {
  run run_hook_pair

  [ "$status" -eq 0 ]
  [[ "$output" == *"Token revoked successfully"* ]]

  # The DELETE must carry the token pre-command actually minted.
  run curl_calls
  [[ "$output" == *"DELETE"*"https://api.github.com/installation/token"* ]]
  [[ "$output" == *"Authorization: token ghs_stubaccesstoken"* ]]
}

@test "does not report the skip path when revocation is enabled" {
  run run_hook_pair

  [ "$status" -eq 0 ]
  [[ "$output" != *"No token available for revocation"* ]]
  [[ "$output" != *"skip-token-revoke=true"* ]]
}

@test "revokes against a custom github-api-url" {
  export BUILDKITE_PLUGIN_CREATE_GITHUB_APP_TOKEN_GITHUB_API_URL="https://github.example.com/api/v3"

  run run_hook_pair

  [ "$status" -eq 0 ]
  [[ "$output" == *"Token revoked successfully"* ]]

  run curl_calls
  [[ "$output" == *"DELETE"*"https://github.example.com/api/v3/installation/token"* ]]
  [[ "$output" != *"https://api.github.com/installation/token"* ]]
}

@test "revokes a token stored in a custom output-variable" {
  export BUILDKITE_PLUGIN_CREATE_GITHUB_APP_TOKEN_OUTPUT_VARIABLE="MY_GITHUB_TOKEN"

  run run_hook_pair

  [ "$status" -eq 0 ]
  [[ "$output" == *"Token revoked successfully"* ]]
  [[ "$output" == *"MY_GITHUB_TOKEN successfully cleared"* ]]
}

@test "skips revocation when skip-token-revoke is true" {
  export BUILDKITE_PLUGIN_CREATE_GITHUB_APP_TOKEN_SKIP_TOKEN_REVOKE="true"

  run run_hook_pair

  [ "$status" -eq 0 ]
  [[ "$output" == *"Token revocation disabled (skip-token-revoke=true)"* ]]
  [[ "$output" != *"Revoking GitHub App token"* ]]

  run curl_calls
  [[ "$output" != *"DELETE"* ]]
}

@test "warns instead of revoking when the token never reaches post-command" {
  # Stands in for a pre-command that failed before minting: post-command runs
  # regardless, and must say the token is still live rather than imply the
  # caller turned revocation off.
  run bash -c '"$POST_COMMAND"'

  [ "$status" -eq 0 ]
  [[ "$output" == *"⚠️"* ]]
  [[ "$output" == *"revocation is enabled but no token was found to revoke"* ]]
  [[ "$output" != *"skip-token-revoke=true"* ]]

  run curl_calls
  [[ "$output" != *"DELETE"* ]]
}
