#!/usr/bin/env bash
# Shared setup for the hook tests.
#
# The hooks talk to the GitHub API with curl and to the agent with
# buildkite-agent; both are replaced by stubs on PATH so the tests are hermetic.
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
  : > "$CURL_LOG"
  : > "$REDACTOR_LOG"

  PATH="${BATS_TEST_DIRNAME}/stubs:${PATH}"
  export PATH CURL_LOG REDACTOR_LOG

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
}

teardown_test_env() {
  [[ -n "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
}

# Every curl invocation, one per line, in call order.
curl_calls() {
  cat "$CURL_LOG"
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
