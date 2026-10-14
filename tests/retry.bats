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
  [[ "$output" == *"Attempt 1/5: POST "*"/access_tokens failed (curl exit 7). Response: not logged after a transport error"* ]]
}

@test "does not retry curl errors that are not transport failures" {
  export STUB_INSTALLATION_HTTP_CODE="exit:60"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 1 ]
  [ "$(calls_to /installation)" -eq 1 ]
  [ -z "$(sleeps)" ]
  [[ "$output" == *"(curl exit 60)"* ]]
}

@test "never logs a token response cut off mid-transfer" {
  export STUB_ACCESS_TOKEN_HTTP_CODE="exit:56:201 201"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 0 ]
  [ "$(calls_to /access_tokens)" -eq 2 ]
  [[ "$output" == *"(curl exit 56 after HTTP 201)"* ]]
  [[ "$output" != *"ghs_"* ]]
}

@test "backs off exponentially with jitter, capped at 30s a step" {
  export BUILDKITE_PLUGIN_CREATE_GITHUB_APP_TOKEN_MAX_ATTEMPTS="7"
  export BUILDKITE_PLUGIN_CREATE_GITHUB_APP_TOKEN_MAX_RETRY_WAIT="1000"
  export STUB_INSTALLATION_HTTP_CODE="500 500 500 500 500 500 200"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 0 ]
  local -a delays=()
  local delay
  while IFS= read -r delay; do
    delays+=("$delay")
  done < "$SLEEP_LOG"
  [ "${#delays[@]}" -eq 6 ]
  [ "${delays[0]}" -ge 2 ] && [ "${delays[0]}" -le 3 ]
  [ "${delays[1]}" -ge 4 ] && [ "${delays[1]}" -le 7 ]
  [ "${delays[2]}" -ge 8 ] && [ "${delays[2]}" -le 15 ]
  for delay in "${delays[@]:3}"; do
    [ "$delay" -ge 16 ] && [ "$delay" -le 30 ]
  done
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
  export STUB_NOW="1700000000"
  export STUB_INSTALLATION_HTTP_CODE="403 200"
  export STUB_RATELIMIT_RESET="1700000020"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 0 ]
  [ "$(calls_to /installation)" -eq 2 ]
  [ "$(sleeps)" = "20" ]
}

@test "waits a minute on a secondary rate limit without headers" {
  export STUB_INSTALLATION_HTTP_CODE="403 200"
  export STUB_ERROR_MESSAGE="You have exceeded a secondary rate limit."

  run bash "$PRE_COMMAND"

  [ "$status" -eq 0 ]
  [ "$(calls_to /installation)" -eq 2 ]
  [ "$(sleeps)" = "60" ]
  [[ "$output" == *"(HTTP 403, secondary rate limit)"* ]]
}

@test "names the secondary rate limit when its wait exceeds max-retry-wait" {
  export BUILDKITE_PLUGIN_CREATE_GITHUB_APP_TOKEN_MAX_RETRY_WAIT="30"
  export STUB_INSTALLATION_HTTP_CODE="403"
  export STUB_ERROR_MESSAGE="You have exceeded a secondary rate limit."

  run bash "$PRE_COMMAND"

  [ "$status" -eq 1 ]
  [ "$(calls_to /installation)" -eq 1 ]
  [ -z "$(sleeps)" ]
  [[ "$output" == *"still failing (HTTP 403, secondary rate limit); waiting 60s more would exceed max-retry-wait (30s)"* ]]
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

@test "reuses one JWT across retries while it is fresh" {
  export STUB_NOW="1700000000"
  export STUB_INSTALLATION_HTTP_CODE="502 502 200"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 0 ]
  # Three lookups and one token request, seconds apart on the simulated clock.
  [ "$(grep -c 'Authorization: Bearer ' "$CURL_LOG")" -eq 4 ]
  [ "$(sent_jwts | wc -l)" -eq 1 ]
}

@test "signs a new JWT once the current one nears expiry" {
  export STUB_NOW="1700000000"
  export BUILDKITE_PLUGIN_CREATE_GITHUB_APP_TOKEN_MAX_RETRY_WAIT="1000"
  export STUB_INSTALLATION_HTTP_CODE="429 200"
  export STUB_RETRY_AFTER="500"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 0 ]
  # 500s later the first JWT has under 120s left, so the retry signs another.
  [ "$(sent_jwts | wc -l)" -eq 2 ]
}

@test "never logs the JWT or the minted token" {
  export STUB_INSTALLATION_HTTP_CODE="502 200"
  export STUB_ACCESS_TOKEN_HTTP_CODE="500 201"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 0 ]
  local jwt
  while IFS= read -r jwt; do
    [[ "$output" != *"$jwt"* ]]
  done < <(sent_jwts)
  [ -n "$(sent_jwts)" ]
  [[ "$output" != *"Bearer"* ]]
  [[ "$output" != *"eyJ"* ]]
  [[ "$output" != *"ghs_"* ]]
}

@test "rejects a max-attempts that is not a positive integer" {
  export BUILDKITE_PLUGIN_CREATE_GITHUB_APP_TOKEN_MAX_ATTEMPTS="0"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 1 ]
  [[ "$output" == *"max-attempts must be a positive integer"* ]]
  [ "$(calls_to /installation)" -eq 0 ]
}
