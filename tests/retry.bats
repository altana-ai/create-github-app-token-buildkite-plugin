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

@test "succeeds after a transient 502 on the installation lookup" {
  export STUB_INSTALLATION_HTTP_CODE="502 200"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 0 ]
  [ "$(calls_to /installation)" -eq 2 ]
  [[ "$output" == *'Attempt 1/5: GET https://api.github.com/repos/test-owner/test-repo/installation failed (HTTP 502). Response: {"message":"stubbed failure"}'* ]]
  [ "$(sleeps | wc -l)" -eq 1 ]
}

@test "succeeds after a curl transport error on the token request" {
  export STUB_ACCESS_TOKEN_HTTP_CODE="exit:7 201"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 0 ]
  [ "$(calls_to /access_tokens)" -eq 2 ]
  [[ "$output" == *"Attempt 1/5: POST "*"/access_tokens failed (curl exit 7). Response: <empty>"* ]]
}

@test "backs off exponentially with jitter" {
  export STUB_INSTALLATION_HTTP_CODE="500 500 500 500 200"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 0 ]
  mapfile -t delays < "$SLEEP_LOG"
  [ "${#delays[@]}" -eq 4 ]
  [ "${delays[0]}" -ge 2 ] && [ "${delays[0]}" -le 3 ]
  [ "${delays[1]}" -ge 4 ] && [ "${delays[1]}" -le 7 ]
  [ "${delays[2]}" -ge 8 ] && [ "${delays[2]}" -le 15 ]
  [ "${delays[3]}" -ge 16 ] && [ "${delays[3]}" -le 31 ]
}

@test "honours Retry-After on a 429" {
  export STUB_ACCESS_TOKEN_HTTP_CODE="429 201"
  export STUB_RETRY_AFTER="7"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 0 ]
  [ "$(calls_to /access_tokens)" -eq 2 ]
  [ "$(sleeps)" = "7" ]
}

@test "honours x-ratelimit-reset on a rate-limited 403" {
  export STUB_INSTALLATION_HTTP_CODE="403 200"
  export STUB_RATELIMIT_RESET="$(( $(date +%s) + 20 ))"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 0 ]
  [ "$(calls_to /installation)" -eq 2 ]
  [ "$(sleeps)" -ge 19 ] && [ "$(sleeps)" -le 20 ]
}

@test "does not retry a 401" {
  export STUB_INSTALLATION_HTTP_CODE="401"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 1 ]
  [ "$(calls_to /installation)" -eq 1 ]
  [ -z "$(sleeps)" ]
  [[ "$output" == *"Failed to get installation information (HTTP 401)"* ]]
}

@test "does not retry a 403 that is not a rate limit" {
  export STUB_INSTALLATION_HTTP_CODE="403"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 1 ]
  [ "$(calls_to /installation)" -eq 1 ]
  [ -z "$(sleeps)" ]
}

@test "does not retry a 404" {
  export STUB_INSTALLATION_HTTP_CODE="404"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 1 ]
  [ "$(calls_to /installation)" -eq 1 ]
  [ -z "$(sleeps)" ]
  [[ "$output" == *"GitHub App is not installed on test-owner/test-repo"* ]]
}

@test "does not retry a 422 on the token request" {
  export STUB_ACCESS_TOKEN_HTTP_CODE="422"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 1 ]
  [ "$(calls_to /access_tokens)" -eq 1 ]
  [ -z "$(sleeps)" ]
  [[ "$output" == *"Failed to generate installation token (HTTP 422)"* ]]
}

@test "fails after the attempt limit, naming the final status" {
  export STUB_INSTALLATION_HTTP_CODE="503"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 1 ]
  [ "$(calls_to /installation)" -eq 5 ]
  [ "$(sleeps | wc -l)" -eq 4 ]
  [[ "$output" == *"still failing after 5 attempts (HTTP 503)"* ]]
  [[ "$output" == *"Failed to get installation information (HTTP 503)"* ]]
}

@test "fails after the attempt limit on transport errors" {
  export STUB_ACCESS_TOKEN_HTTP_CODE="exit:28"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 1 ]
  [ "$(calls_to /access_tokens)" -eq 5 ]
  [[ "$output" == *"still failing after 5 attempts (curl exit 28)"* ]]
  [[ "$output" == *"Failed to generate installation token (HTTP 000)"* ]]
}

@test "honours max-attempts" {
  export BUILDKITE_PLUGIN_CREATE_GITHUB_APP_TOKEN_MAX_ATTEMPTS="2"
  export STUB_INSTALLATION_HTTP_CODE="503"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 1 ]
  [ "$(calls_to /installation)" -eq 2 ]
  [[ "$output" == *"still failing after 2 attempts (HTTP 503)"* ]]
}

@test "gives up when Retry-After exceeds max-retry-wait" {
  export STUB_ACCESS_TOKEN_HTTP_CODE="429"
  export STUB_RETRY_AFTER="3600"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 1 ]
  [ "$(calls_to /access_tokens)" -eq 1 ]
  [ -z "$(sleeps)" ]
  [[ "$output" == *"would exceed max-retry-wait (60s)"* ]]
  [[ "$output" == *"Failed to generate installation token (HTTP 429)"* ]]
}

@test "never logs the JWT or the minted token" {
  export STUB_INSTALLATION_HTTP_CODE="502 200"
  export STUB_ACCESS_TOKEN_HTTP_CODE="500 201"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 0 ]
  [[ "$output" != *"Bearer"* ]]
  [[ "$output" != *"$STUB_ACCESS_TOKEN"* ]]
}

@test "rejects a max-attempts that is not a positive integer" {
  export BUILDKITE_PLUGIN_CREATE_GITHUB_APP_TOKEN_MAX_ATTEMPTS="0"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 1 ]
  [[ "$output" == *"max-attempts must be a positive integer"* ]]
  [ "$(calls_to /installation)" -eq 0 ]
}
