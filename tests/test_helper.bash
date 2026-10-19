#!/usr/bin/env bash
# Shared setup for the hook tests.
#
# The hooks talk to the GitHub API with curl and to the agent with
# buildkite-agent; both are replaced by stubs on PATH so the tests are hermetic.
# sleep is stubbed too, so retry backoff is recorded rather than waited out, and
# date can run on a simulated clock that those recorded delays advance. rm is a
# spy that can record the environment the hook's child processes inherit.
# openssl is *not* stubbed — a throwaway RSA key is generated once per file so
# the JWT signing path runs for real.

PLUGIN_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
export PLUGIN_ROOT

PRE_COMMAND="${PLUGIN_ROOT}/hooks/pre-command"
POST_COMMAND="${PLUGIN_ROOT}/hooks/post-command"
export PRE_COMMAND POST_COMMAND

# Generate the RSA key once per test file rather than once per test — genrsa is
# the slowest thing in the suite.
generate_test_key() {
  BATS_FILE_TMPDIR="${BATS_FILE_TMPDIR:-$(mktemp -d)}"
  TEST_PRIVATE_KEY_FILE="${BATS_FILE_TMPDIR}/private-key.pem"
  openssl genrsa -out "$TEST_PRIVATE_KEY_FILE" 2048 2>/dev/null
  export BATS_FILE_TMPDIR TEST_PRIVATE_KEY_FILE
}

# Stub PATH plus the plugin configuration a passing run needs. Individual tests
# override or unset these before invoking a hook.
setup_test_env() {
  TEST_TMPDIR="$(mktemp -d)"
  CURL_LOG="${TEST_TMPDIR}/curl.log"
  REDACTOR_LOG="${TEST_TMPDIR}/redactor.log"
  SLEEP_LOG="${TEST_TMPDIR}/sleep.log"
  CLOCK_LOG="${TEST_TMPDIR}/clock.log"
  : > "$CURL_LOG"
  : > "$REDACTOR_LOG"
  : > "$SLEEP_LOG"
  : > "$CLOCK_LOG"

  PATH="${BATS_TEST_DIRNAME}/stubs:${PATH}"
  export PATH CURL_LOG REDACTOR_LOG SLEEP_LOG CLOCK_LOG

  # Stub controls from the developer's shell would change what every stub answers.
  local control
  while IFS= read -r control; do
    unset "$control"
  done < <(compgen -e | grep -E '^(STUB_|ENV_SPY_LOG$)' || true)

  export STUB_ACCESS_TOKEN="ghs_stubaccesstoken"
  export STUB_INSTALLATION_ID="87654321"

  export BUILDKITE_REPO="git@github.com:test-owner/test-repo.git"
  export BUILDKITE_PLUGIN_CREATE_GITHUB_APP_TOKEN_APP_ID="123456"
  export BUILDKITE_PLUGIN_CREATE_GITHUB_APP_TOKEN_PRIVATE_KEY
  BUILDKITE_PLUGIN_CREATE_GITHUB_APP_TOKEN_PRIVATE_KEY="$(cat "$TEST_PRIVATE_KEY_FILE")"

  # A caller-provided token must never survive into a test as a false positive.
  unset GITHUB_TOKEN GITHUB_APP_TOKEN_FOR_REVOCATION GITHUB_API_URL_FOR_REVOCATION
  unset BUILDKITE_PLUGIN_CREATE_GITHUB_APP_TOKEN_SKIP_TOKEN_REVOKE
  unset BUILDKITE_PLUGIN_CREATE_GITHUB_APP_TOKEN_GITHUB_API_URL
  unset BUILDKITE_PLUGIN_CREATE_GITHUB_APP_TOKEN_OUTPUT_VARIABLE
  unset BUILDKITE_PLUGIN_CREATE_GITHUB_APP_TOKEN_OWNER
  unset BUILDKITE_PLUGIN_CREATE_GITHUB_APP_TOKEN_REPOSITORIES
  unset BUILDKITE_PLUGIN_CREATE_GITHUB_APP_TOKEN_MAX_ATTEMPTS
  unset BUILDKITE_PLUGIN_CREATE_GITHUB_APP_TOKEN_MAX_RETRY_WAIT

  # Permissions are read by scanning the environment, so a stray export from the
  # developer's shell would end up in the token request.
  local permission
  while IFS= read -r permission; do
    unset "$permission"
  done < <(compgen -e | grep '^BUILDKITE_PLUGIN_CREATE_GITHUB_APP_TOKEN_PERMISSION_' || true)
}

teardown_test_env() {
  [[ -n "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
}

# Every curl invocation, one per line, in call order.
curl_calls() {
  cat "$CURL_LOG"
}

# How many requests went to URLs ending in the given path.
calls_to() {
  grep -c -- "${1}\$" "$CURL_LOG"
}

# Output assertions that fail the test on every bash: before 4.1, a failing
# `[[ ]]` that is not a test's last command is ignored.
# shellcheck disable=SC2154 # bats `run` sets output
assert_output_contains() {
  [[ "$output" == *"$1"* ]] || { echo "expected output to contain: $1"; return 1; }
}

refute_output_contains() {
  [[ "$output" != *"$1"* ]] || { echo "expected output not to contain: $1"; return 1; }
}

# How many times the output contains a string.
output_count() {
  grep -oF -- "$1" <<< "$output" | wc -l | tr -d ' '
}

# The distinct JWTs the hook sent, one per line.
sent_jwts() {
  grep -o 'Authorization: Bearer [^ ]*' "$CURL_LOG" | cut -d' ' -f3 | sort -u
}

# Every delay the hook slept for, one per line.
sleeps() {
  cat "$SLEEP_LOG"
}

# The JSON body posted to the access_tokens endpoint. It is compact, so it is the
# only whitespace-free `{...}` field in the recorded invocation.
token_request_body() {
  sed -n 's/.* -d \({[^ ]*}\).*/\1/p' "$CURL_LOG"
}

# Run pre-command and then post-command the way buildkite-agent does: the hook
# body is sourced, and the next hook runs as a child process. Only *exported*
# variables cross that boundary, which is exactly what regressed.
run_hook_pair() {
  bash -c '
    set -euo pipefail
    source "$PRE_COMMAND"
    "$POST_COMMAND"
  '
}
