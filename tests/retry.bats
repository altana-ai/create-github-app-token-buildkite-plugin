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
  assert_output_contains 'Attempt 1/5: GET https://api.github.com/repos/test-owner/test-repo/installation failed (HTTP 502). Response: {"message":"stubbed failure"}'
  [ "$(sleeps | wc -l)" -eq 1 ]
}

@test "succeeds after a curl transport error on the token request" {
  export STUB_ACCESS_TOKEN_HTTP_CODE="exit:7 201"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 0 ]
  [ "$(calls_to /access_tokens)" -eq 2 ]
  assert_output_contains "Attempt 1/5: POST "
  assert_output_contains "/access_tokens failed (curl exit 7). Response: not logged after a transport error"
}

@test "keeps the status received before a transport error" {
  export STUB_INSTALLATION_HTTP_CODE="exit:18:503 200"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 0 ]
  assert_output_contains "(curl exit 18 after HTTP 503)"
}

@test "treats a transport error after a 404 as the 404" {
  export STUB_INSTALLATION_HTTP_CODE="exit:28:404"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 1 ]
  [ "$(calls_to /installation)" -eq 1 ]
  [ -z "$(sleeps)" ]
  assert_output_contains "GitHub App is not installed on test-owner/test-repo"
}

@test "does not retry curl errors that are not transport failures" {
  export STUB_INSTALLATION_HTTP_CODE="exit:60"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 1 ]
  [ "$(calls_to /installation)" -eq 1 ]
  [ -z "$(sleeps)" ]
  assert_output_contains "Failed to get installation information (curl exit 60)"
}

@test "never logs a token response cut off mid-transfer" {
  export STUB_ACCESS_TOKEN_HTTP_CODE="exit:56:201 201"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 0 ]
  [ "$(calls_to /access_tokens)" -eq 2 ]
  assert_output_contains "(curl exit 56 after HTTP 201)"
  refute_output_contains "ghs_"
}

@test "accepts a token from any 2xx and never logs it" {
  export STUB_ACCESS_TOKEN_HTTP_CODE="200"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 0 ]
  refute_output_contains "ghs_"
  run cat "$REDACTOR_LOG"
  assert_output_contains "redactor add"
}

@test "masks token-shaped strings in a logged body" {
  export STUB_ACCESS_TOKEN_HTTP_CODE="422"
  export STUB_ERROR_MESSAGE="rejected ghs_leakedtoken ghr_refresh github_pat_finegrained"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 1 ]
  refute_output_contains "ghs_leakedtoken"
  refute_output_contains "ghr_refresh"
  refute_output_contains "github_pat_finegrained"
  assert_output_contains "rejected [REDACTED] [REDACTED] [REDACTED]"
}

@test "keeps secrets out of the environment of child processes" {
  export output="preset" body="preset" url="preset" header_file="preset" headers="preset"
  export ENV_SPY_LOG="${TEST_TMPDIR}/env.log"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 0 ]
  [ -s "$ENV_SPY_LOG" ]
  local -a jwts=()
  local jwt
  while IFS= read -r jwt; do
    jwts+=("$jwt")
  done < <(sent_jwts)
  [ "${#jwts[@]}" -gt 0 ]
  # Every environment rm inherited, the stub's own STUB_ACCESS_TOKEN aside.
  run grep -v '^STUB_ACCESS_TOKEN=' "$ENV_SPY_LOG"
  refute_output_contains "ghs_"
  for jwt in "${jwts[@]}"; do
    refute_output_contains "$jwt"
  done
}

@test "keeps the JWT and the token out of same-named exported variables" {
  export jwt_token="preset" access_token="preset" api_body="preset"
  export _cgat_jwt="preset" _cgat_access_token="preset" _cgat_body="preset"

  run bash -c 'source "$PRE_COMMAND" >/dev/null 2>&1; export -p'

  [ "$status" -eq 0 ]
  [ -n "$(sent_jwts)" ]
  local jwt
  while IFS= read -r jwt; do
    refute_output_contains "$jwt"
  done < <(sent_jwts)
  # The token is exported only where the plugin hands it to the job and post-command
  # (the stub's own STUB_ACCESS_TOKEN aside).
  [ "$(grep -F "$STUB_ACCESS_TOKEN" <<< "$output" | grep -vc '^declare -x STUB_ACCESS_TOKEN=')" -eq 2 ]
  assert_output_contains "GITHUB_TOKEN=\"$STUB_ACCESS_TOKEN\""
  assert_output_contains "GITHUB_APP_TOKEN_FOR_REVOCATION=\"$STUB_ACCESS_TOKEN\""
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
  [ "${delays[0]}" -ge 2 ]
  [ "${delays[0]}" -le 3 ]
  [ "${delays[1]}" -ge 4 ]
  [ "${delays[1]}" -le 7 ]
  [ "${delays[2]}" -ge 8 ]
  [ "${delays[2]}" -le 15 ]
  for delay in "${delays[@]:3}"; do
    [ "$delay" -ge 16 ]
    [ "$delay" -le 30 ]
  done
}

@test "honours Retry-After on a 429, with up to 25% jitter" {
  export STUB_ACCESS_TOKEN_HTTP_CODE="429 201"
  export STUB_RETRY_AFTER="8"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 0 ]
  [ "$(calls_to /access_tokens)" -eq 2 ]
  [ "$(sleeps)" -ge 8 ]
  [ "$(sleeps)" -le 10 ]
}

@test "a Retry-After that fits the budget is never pushed past it by jitter" {
  export STUB_ACCESS_TOKEN_HTTP_CODE="429 201"
  export STUB_RETRY_AFTER="120"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 0 ]
  [ "$(sleeps)" -eq 120 ]
}

@test "never waits less than the backoff step for a zero Retry-After" {
  export STUB_ACCESS_TOKEN_HTTP_CODE="429 201"
  export STUB_RETRY_AFTER="0"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 0 ]
  [ "$(sleeps)" -ge 2 ]
  [ "$(sleeps)" -le 3 ]
}

@test "never waits less than the backoff step for a reset in the past" {
  export STUB_NOW="1700000000"
  export STUB_INSTALLATION_HTTP_CODE="403 200"
  export STUB_RATELIMIT_RESET="1699999000"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 0 ]
  [ "$(sleeps)" -ge 2 ]
  [ "$(sleeps)" -le 3 ]
}

@test "ignores x-ratelimit-reset on a 5xx" {
  export STUB_NOW="1700000000"
  export STUB_INSTALLATION_HTTP_CODE="502 200"
  export STUB_RATELIMIT_RESET="1700003600"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 0 ]
  [ "$(sleeps)" -ge 2 ]
  [ "$(sleeps)" -le 3 ]
}

@test "honours x-ratelimit-reset on a rate-limited 403" {
  export STUB_NOW="1700000000"
  export STUB_INSTALLATION_HTTP_CODE="403 200"
  export STUB_RATELIMIT_RESET="1700000020"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 0 ]
  [ "$(calls_to /installation)" -eq 2 ]
  [ "$(sleeps)" -ge 20 ]
  [ "$(sleeps)" -le 25 ]
}

@test "waits a minute on a secondary rate limit without headers" {
  export STUB_INSTALLATION_HTTP_CODE="403 200"
  export STUB_ERROR_MESSAGE="You have exceeded a secondary rate limit."

  run bash "$PRE_COMMAND"

  [ "$status" -eq 0 ]
  [ "$(calls_to /installation)" -eq 2 ]
  [ "$(sleeps)" -ge 60 ]
  [ "$(sleeps)" -le 75 ]
  assert_output_contains "(HTTP 403, secondary rate limit)"
}

@test "doubles the wait for consecutive secondary rate limits" {
  export BUILDKITE_PLUGIN_CREATE_GITHUB_APP_TOKEN_MAX_RETRY_WAIT="1000"
  export STUB_INSTALLATION_HTTP_CODE="403 403 200"
  export STUB_ERROR_MESSAGE="You have exceeded a secondary rate limit."

  run bash "$PRE_COMMAND"

  [ "$status" -eq 0 ]
  local -a delays=()
  local delay
  while IFS= read -r delay; do
    delays+=("$delay")
  done < "$SLEEP_LOG"
  [ "${#delays[@]}" -eq 2 ]
  [ "${delays[0]}" -ge 60 ]
  [ "${delays[0]}" -le 75 ]
  [ "${delays[1]}" -ge 120 ]
  [ "${delays[1]}" -le 150 ]
}

@test "treats an abuse detection 403 as a secondary rate limit" {
  export STUB_INSTALLATION_HTTP_CODE="403 200"
  export STUB_ERROR_MESSAGE="You have triggered an abuse detection mechanism."

  run bash "$PRE_COMMAND"

  [ "$status" -eq 0 ]
  [ "$(sleeps)" -ge 60 ]
  [ "$(sleeps)" -le 75 ]
  assert_output_contains "(HTTP 403, secondary rate limit)"
}

@test "fits a secondary rate limit wait after backoff within the default budget" {
  export STUB_INSTALLATION_HTTP_CODE="502 502 502 403 200"
  export STUB_ERROR_MESSAGE="You have exceeded a secondary rate limit."

  run bash "$PRE_COMMAND"

  [ "$status" -eq 0 ]
  [ "$(calls_to /installation)" -eq 5 ]
}

@test "names the secondary rate limit when its wait exceeds max-retry-wait" {
  export BUILDKITE_PLUGIN_CREATE_GITHUB_APP_TOKEN_MAX_RETRY_WAIT="30"
  export STUB_INSTALLATION_HTTP_CODE="403"
  export STUB_ERROR_MESSAGE="You have exceeded a secondary rate limit."

  run bash "$PRE_COMMAND"

  [ "$status" -eq 1 ]
  [ "$(calls_to /installation)" -eq 1 ]
  [ -z "$(sleeps)" ]
  assert_output_contains "still failing (HTTP 403, secondary rate limit); its next wait would exceed max-retry-wait (30s)"
}

@test "does not retry a 401, and logs its body once" {
  export STUB_INSTALLATION_HTTP_CODE="401"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 1 ]
  [ "$(calls_to /installation)" -eq 1 ]
  [ -z "$(sleeps)" ]
  refute_output_contains "Attempt 1/5"
  assert_output_contains "Failed to get installation information (HTTP 401)"
  [ "$(output_count "stubbed failure")" -eq 1 ]
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
  assert_output_contains "GitHub App is not installed on test-owner/test-repo"
}

@test "does not retry a 422 on the token request" {
  export STUB_ACCESS_TOKEN_HTTP_CODE="422"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 1 ]
  [ "$(calls_to /access_tokens)" -eq 1 ]
  [ -z "$(sleeps)" ]
  assert_output_contains "Failed to generate installation token (HTTP 422)"
}

@test "fails after the attempt limit, naming the final status" {
  export STUB_INSTALLATION_HTTP_CODE="503"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 1 ]
  [ "$(calls_to /installation)" -eq 5 ]
  [ "$(sleeps | wc -l)" -eq 4 ]
  assert_output_contains "still failing after 5 attempts (HTTP 503)"
  assert_output_contains "Failed to get installation information (HTTP 503)"
  # One body per attempt: four retried attempts, then the final one.
  refute_output_contains "Attempt 5/5"
  [ "$(output_count "stubbed failure")" -eq 5 ]
}

@test "fails after the attempt limit on transport errors" {
  export STUB_ACCESS_TOKEN_HTTP_CODE="exit:28"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 1 ]
  [ "$(calls_to /access_tokens)" -eq 5 ]
  assert_output_contains "still failing after 5 attempts (curl exit 28)"
  assert_output_contains "Failed to generate installation token (curl exit 28)"
}

@test "honours max-attempts" {
  export BUILDKITE_PLUGIN_CREATE_GITHUB_APP_TOKEN_MAX_ATTEMPTS="2"
  export STUB_INSTALLATION_HTTP_CODE="503"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 1 ]
  [ "$(calls_to /installation)" -eq 2 ]
  assert_output_contains "still failing after 2 attempts (HTTP 503)"
}

@test "gives up when Retry-After exceeds max-retry-wait" {
  export STUB_ACCESS_TOKEN_HTTP_CODE="429"
  export STUB_RETRY_AFTER="3600"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 1 ]
  [ "$(calls_to /access_tokens)" -eq 1 ]
  [ -z "$(sleeps)" ]
  assert_output_contains "would exceed max-retry-wait (120s)"
  assert_output_contains "Failed to generate installation token (HTTP 429, rate limit)"
}

@test "reuses one JWT across retries while it is fresh" {
  export STUB_NOW="1700000000"
  export STUB_CLOCK_TICK="1"
  export STUB_INSTALLATION_HTTP_CODE="502 502 200"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 0 ]
  # Three lookups and one token request, seconds apart on the simulated clock.
  [ "$(grep -c 'Authorization: Bearer ' "$CURL_LOG")" -eq 4 ]
  [ "$(sent_jwts | wc -l)" -eq 1 ]
}

@test "signs a new JWT once the current one nears expiry, and keeps it" {
  export STUB_NOW="1700000000"
  export STUB_CLOCK_TICK="1"
  export BUILDKITE_PLUGIN_CREATE_GITHUB_APP_TOKEN_MAX_RETRY_WAIT="1000"
  export STUB_INSTALLATION_HTTP_CODE="429 200"
  export STUB_RETRY_AFTER="500"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 0 ]
  # 500s later the first JWT has under 120s left, so the retry signs another,
  # and the token request reuses that one rather than signing a third.
  [ "$(sent_jwts | wc -l)" -eq 2 ]
}

@test "never logs the JWT or the minted token" {
  export STUB_INSTALLATION_HTTP_CODE="502 200"
  export STUB_ACCESS_TOKEN_HTTP_CODE="500 201"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 0 ]
  [ -n "$(sent_jwts)" ]
  local jwt
  while IFS= read -r jwt; do
    refute_output_contains "$jwt"
  done < <(sent_jwts)
  refute_output_contains "Bearer"
  refute_output_contains "eyJ"
  refute_output_contains "ghs_"
}

@test "rejects a max-retry-wait with leading zeros" {
  local value
  for value in 090 010; do
    export BUILDKITE_PLUGIN_CREATE_GITHUB_APP_TOKEN_MAX_RETRY_WAIT="$value"

    run bash "$PRE_COMMAND"

    [ "$status" -eq 1 ]
    assert_output_contains "max-retry-wait must be a non-negative integer, got '$value'"
  done
  [ "$(calls_to /installation)" -eq 0 ]
}

@test "rejects a max-attempts that is not a positive integer" {
  export BUILDKITE_PLUGIN_CREATE_GITHUB_APP_TOKEN_MAX_ATTEMPTS="0"

  run bash "$PRE_COMMAND"

  [ "$status" -eq 1 ]
  assert_output_contains "max-attempts must be a positive integer"
  [ "$(calls_to /installation)" -eq 0 ]
}
