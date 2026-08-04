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

@test "revokes the token it is handed" {
  export GITHUB_APP_TOKEN_FOR_REVOCATION="ghs_handedtoken"

  run bash "$POST_COMMAND"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Token revoked successfully"* ]]

  run curl_calls
  [[ "$output" == *"Authorization: token ghs_handedtoken"* ]]
}

@test "defaults to api.github.com when no revocation api url is set" {
  export GITHUB_APP_TOKEN_FOR_REVOCATION="ghs_handedtoken"

  run bash "$POST_COMMAND"

  [ "$status" -eq 0 ]
  run curl_calls
  [[ "$output" == *"https://api.github.com/installation/token"* ]]
}

@test "revokes against the api url pre-command recorded" {
  export GITHUB_APP_TOKEN_FOR_REVOCATION="ghs_handedtoken"
  export GITHUB_API_URL_FOR_REVOCATION="https://github.example.com/api/v3"

  run bash "$POST_COMMAND"

  [ "$status" -eq 0 ]
  run curl_calls
  [[ "$output" == *"https://github.example.com/api/v3/installation/token"* ]]
}

@test "warns without failing the step when revocation is rejected" {
  export GITHUB_APP_TOKEN_FOR_REVOCATION="ghs_handedtoken"
  export STUB_REVOKE_HTTP_CODE="401"

  run bash "$POST_COMMAND"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Token revocation failed (HTTP 401)"* ]]
}

@test "skips revocation when skip-token-revoke is true" {
  export BUILDKITE_PLUGIN_CREATE_GITHUB_APP_TOKEN_SKIP_TOKEN_REVOKE="true"
  export GITHUB_APP_TOKEN_FOR_REVOCATION="ghs_handedtoken"

  run bash "$POST_COMMAND"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Token revocation disabled (skip-token-revoke=true)"* ]]

  run curl_calls
  [[ "$output" != *"DELETE"* ]]
}

@test "warns when revocation is enabled but no token is present" {
  run bash "$POST_COMMAND"

  [ "$status" -eq 0 ]
  [[ "$output" == *"⚠️"* ]]
  [[ "$output" == *"revocation is enabled but no token was found to revoke"* ]]
  # The old message blamed skip-token-revoke, which is knowable here and false.
  [[ "$output" != *"skip-token-revoke=true"* ]]
}

@test "clears the output variable from the environment" {
  export GITHUB_TOKEN="ghs_handedtoken"

  run bash "$POST_COMMAND"

  [ "$status" -eq 0 ]
  [[ "$output" == *"GITHUB_TOKEN successfully cleared"* ]]
}

@test "clears a custom output variable from the environment" {
  export BUILDKITE_PLUGIN_CREATE_GITHUB_APP_TOKEN_OUTPUT_VARIABLE="MY_GITHUB_TOKEN"
  export MY_GITHUB_TOKEN="ghs_handedtoken"

  run bash "$POST_COMMAND"

  [ "$status" -eq 0 ]
  [[ "$output" == *"MY_GITHUB_TOKEN successfully cleared"* ]]
}

@test "reports nothing to clean up when the output variable is unset" {
  run bash "$POST_COMMAND"

  [ "$status" -eq 0 ]
  [[ "$output" == *"GITHUB_TOKEN is not set (nothing to clean up)"* ]]
}
