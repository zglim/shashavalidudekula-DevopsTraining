#!/bin/bash
#
# Regression tests for JenkinsJobsAutomation.sh
# Run: bash Jenkins/test_JenkinsJobsAutomation.sh
#

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/JenkinsJobsAutomation.sh"

PASS=0
FAIL=0
TOTAL=0

##############################################################################
# Helpers
##############################################################################
setup_tempdir() {
    TMPDIR_TEST="$(mktemp -d)"
    # Create a dummy jenkins-cli.jar so the -f check passes
    touch "$TMPDIR_TEST/jenkins-cli.jar"
    # Create a fake java that records its arguments and succeeds
    cat > "$TMPDIR_TEST/java" <<'FAKEJAVA'
#!/bin/bash
echo "FAKEJAVA_ARGS: $*"
exit 0
FAKEJAVA
    chmod +x "$TMPDIR_TEST/java"
}

teardown_tempdir() {
    rm -rf "$TMPDIR_TEST"
}

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [[ "$expected" == "$actual" ]]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected: $expected"
        echo "    actual  : $actual"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL + 1))
    if echo "$haystack" | grep -qF -- "$needle"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected to contain: $needle"
        echo "    actual output      : $haystack"
        FAIL=$((FAIL + 1))
    fi
}

assert_not_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL + 1))
    if ! echo "$haystack" | grep -qF -- "$needle"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected NOT to contain: $needle"
        echo "    actual output          : $haystack"
        FAIL=$((FAIL + 1))
    fi
}

# Run the script in a subshell, capturing stdout+stderr, returning exit code.
# Prepend our fake java to PATH so run_jenkins_cli uses it.
run_script() {
    PATH="$TMPDIR_TEST:$PATH" bash "$SCRIPT" "$@" 2>&1
}

##############################################################################
# Test: --help flag
##############################################################################
test_help_flag() {
    echo "[Test] --help flag shows usage"
    setup_tempdir
    local out
    out=$(run_script --help)
    local rc=$?
    assert_eq "--help exits 0" "0" "$rc"
    assert_contains "--help shows Usage header" "Usage:" "$out"
    assert_contains "--help mentions --action" "--action" "$out"
    assert_contains "--help mentions --job" "--job" "$out"
    teardown_tempdir
}

##############################################################################
# Test: Missing connection info
##############################################################################
test_missing_connection_info() {
    echo "[Test] Missing connection info produces errors"
    setup_tempdir

    # Unset all env vars, provide action to skip interactive menu
    local out
    out=$(JENKINS_URL="" JENKINS_USERNAME="" JENKINS_TOKEN="" \
          JENKINS_CLI_JAR="$TMPDIR_TEST/jenkins-cli.jar" \
          run_script --action list 2>&1)
    local rc=$?

    assert_eq "exits non-zero when connection info missing" "1" "$rc"
    assert_contains "error mentions Jenkins URL" "Jenkins URL" "$out"
    assert_contains "error mentions username" "username" "$out"
    assert_contains "error mentions token" "token" "$out"
    teardown_tempdir
}

test_missing_url_only() {
    echo "[Test] Missing URL only"
    setup_tempdir
    local out
    out=$(JENKINS_URL="" JENKINS_USERNAME="admin" JENKINS_TOKEN="tok" \
          JENKINS_CLI_JAR="$TMPDIR_TEST/jenkins-cli.jar" \
          run_script --action list 2>&1)
    local rc=$?
    assert_eq "exits non-zero" "1" "$rc"
    assert_contains "mentions URL" "Jenkins URL" "$out"
    assert_not_contains "does not complain about username" "username is not set" "$out"
    teardown_tempdir
}

##############################################################################
# Test: Missing jenkins-cli.jar
##############################################################################
test_missing_jar() {
    echo "[Test] Missing jenkins-cli.jar produces error"
    setup_tempdir
    local out
    out=$(JENKINS_URL="http://x" JENKINS_USERNAME="u" JENKINS_TOKEN="t" \
          JENKINS_CLI_JAR="$TMPDIR_TEST/nonexistent.jar" \
          run_script --action list 2>&1)
    local rc=$?
    assert_eq "exits non-zero when jar missing" "1" "$rc"
    assert_contains "error mentions jar" "jenkins-cli.jar" "$out"
    teardown_tempdir
}

##############################################################################
# Test: Missing job name for actions that need it
##############################################################################
test_missing_job_name() {
    echo "[Test] Missing job name for build/delete/disable/enable/reload"
    setup_tempdir

    for action in build delete disable enable reload; do
        local out
        out=$(JENKINS_URL="http://x" JENKINS_USERNAME="u" JENKINS_TOKEN="t" \
              JENKINS_CLI_JAR="$TMPDIR_TEST/jenkins-cli.jar" \
              run_script --action "$action" 2>&1)
        local rc=$?
        assert_eq "$action exits non-zero without job name" "1" "$rc"
        assert_contains "$action error mentions job name" "requires a job name" "$out"
    done
    teardown_tempdir
}

##############################################################################
# Test: list action does NOT need a job name
##############################################################################
test_list_no_job_needed() {
    echo "[Test] list action works without --job"
    setup_tempdir
    local out
    out=$(JENKINS_URL="http://jenkins:8080" JENKINS_USERNAME="admin" JENKINS_TOKEN="tok" \
          JENKINS_CLI_JAR="$TMPDIR_TEST/jenkins-cli.jar" \
          run_script --action list 2>&1)
    local rc=$?
    assert_eq "list exits 0" "0" "$rc"
    assert_contains "list output shows Listing" "Listing all jobs" "$out"
    assert_contains "list shows SUCCESS in summary" "SUCCESS" "$out"
    teardown_tempdir
}

##############################################################################
# Test: Non-interactive CLI invocation (build with --job)
##############################################################################
test_noninteractive_build() {
    echo "[Test] Non-interactive build via --action and --job"
    setup_tempdir
    local out
    out=$(JENKINS_URL="http://jenkins:8080" JENKINS_USERNAME="admin" JENKINS_TOKEN="tok" \
          JENKINS_CLI_JAR="$TMPDIR_TEST/jenkins-cli.jar" \
          run_script --action build --job my-pipeline 2>&1)
    local rc=$?
    assert_eq "build exits 0" "0" "$rc"
    assert_contains "output shows Building" "Building job my-pipeline" "$out"
    assert_contains "summary shows action" "Action : build" "$out"
    assert_contains "summary shows job" "Job    : my-pipeline" "$out"
    assert_contains "summary shows server" "Server : http://jenkins:8080" "$out"
    assert_contains "summary shows SUCCESS" "SUCCESS" "$out"
    teardown_tempdir
}

##############################################################################
# Test: Command construction correctness (verify java args)
##############################################################################
test_command_construction() {
    echo "[Test] Command construction correctness"
    setup_tempdir

    # The fake java prints FAKEJAVA_ARGS: <args>
    for action_pair in "list:list-jobs" "build:build" "delete:delete-job" \
                       "disable:disable-job" "enable:enable-job" "reload:reload-job"; do
        local action="${action_pair%%:*}"
        local cli_cmd="${action_pair##*:}"
        local job_flag=""
        if [[ "$action" != "list" ]]; then
            job_flag="--job testjob"
        fi
        local out
        out=$(JENKINS_URL="http://srv" JENKINS_USERNAME="usr" JENKINS_TOKEN="tkn" \
              JENKINS_CLI_JAR="$TMPDIR_TEST/jenkins-cli.jar" \
              run_script --action "$action" $job_flag 2>&1)

        assert_contains "$action passes -s http://srv" "-s http://srv" "$out"
        assert_contains "$action passes -auth usr:tkn" "-auth usr:tkn" "$out"
        assert_contains "$action passes -webSocket" "-webSocket" "$out"
        assert_contains "$action passes jenkins CLI command '$cli_cmd'" "$cli_cmd" "$out"

        if [[ "$action" != "list" ]]; then
            assert_contains "$action passes job name" "testjob" "$out"
        fi
    done
    teardown_tempdir
}

##############################################################################
# Test: Interactive menu entry (pipe input)
##############################################################################
test_interactive_menu() {
    echo "[Test] Interactive menu with piped input"
    setup_tempdir

    # Send "1\n" to select "List Jobs"
    local out
    out=$(echo "1" | \
          JENKINS_URL="http://srv" JENKINS_USERNAME="usr" JENKINS_TOKEN="tkn" \
          JENKINS_CLI_JAR="$TMPDIR_TEST/jenkins-cli.jar" \
          PATH="$TMPDIR_TEST:$PATH" bash "$SCRIPT" 2>&1)
    local rc=$?

    assert_eq "interactive list exits 0" "0" "$rc"
    assert_contains "shows menu" "Select a Choice" "$out"
    assert_contains "shows Listing" "Listing all jobs" "$out"
    assert_contains "summary shows SUCCESS" "SUCCESS" "$out"

    # Send "2\nmyjob\n" to select Build + provide job name
    out=$(printf "2\nmyjob\n" | \
          JENKINS_URL="http://srv" JENKINS_USERNAME="usr" JENKINS_TOKEN="tkn" \
          JENKINS_CLI_JAR="$TMPDIR_TEST/jenkins-cli.jar" \
          PATH="$TMPDIR_TEST:$PATH" bash "$SCRIPT" 2>&1)
    rc=$?
    assert_eq "interactive build exits 0" "0" "$rc"
    assert_contains "shows Building" "Building job myjob" "$out"

    teardown_tempdir
}

##############################################################################
# Test: CLI params override env vars
##############################################################################
test_cli_overrides_env() {
    echo "[Test] CLI params override environment variables"
    setup_tempdir
    local out
    out=$(JENKINS_URL="http://env-url" JENKINS_USERNAME="env-user" JENKINS_TOKEN="env-tok" \
          JENKINS_CLI_JAR="$TMPDIR_TEST/jenkins-cli.jar" \
          run_script --url "http://cli-url" --user "cli-user" --token "cli-tok" \
          --action list 2>&1)
    local rc=$?
    assert_eq "exits 0" "0" "$rc"
    assert_contains "uses CLI url" "Server : http://cli-url" "$out"
    assert_contains "java gets CLI auth" "-auth cli-user:cli-tok" "$out"
    teardown_tempdir
}

##############################################################################
# Test: Unknown option
##############################################################################
test_unknown_option() {
    echo "[Test] Unknown option produces error"
    setup_tempdir
    local out
    out=$(run_script --bogus 2>&1)
    local rc=$?
    assert_eq "exits non-zero" "1" "$rc"
    assert_contains "error mentions unknown option" "Unknown option" "$out"
    teardown_tempdir
}

##############################################################################
# Test: Invalid action
##############################################################################
test_invalid_action() {
    echo "[Test] Invalid action name"
    setup_tempdir
    local out
    out=$(JENKINS_URL="http://x" JENKINS_USERNAME="u" JENKINS_TOKEN="t" \
          JENKINS_CLI_JAR="$TMPDIR_TEST/jenkins-cli.jar" \
          run_script --action bogus 2>&1)
    local rc=$?
    assert_eq "exits non-zero" "1" "$rc"
    assert_contains "error mentions unknown action" "Unknown action" "$out"
    teardown_tempdir
}

##############################################################################
# Run all tests
##############################################################################
echo "========================================"
echo " JenkinsJobsAutomation.sh — Regression Tests"
echo "========================================"
echo

test_help_flag
test_missing_connection_info
test_missing_url_only
test_missing_jar
test_missing_job_name
test_list_no_job_needed
test_noninteractive_build
test_command_construction
test_interactive_menu
test_cli_overrides_env
test_unknown_option
test_invalid_action

echo
echo "========================================"
echo " Results: $PASS passed, $FAIL failed, $TOTAL total"
echo "========================================"

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
exit 0
