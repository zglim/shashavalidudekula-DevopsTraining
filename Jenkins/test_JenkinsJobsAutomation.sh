#!/bin/bash
# Regression tests for JenkinsJobsAutomation.sh
# Run from the same directory as the script, or pass the script path as $1.
set -uo pipefail

SCRIPT="${1:-$(dirname "$0")/JenkinsJobsAutomation.sh}"
PASS=0
FAIL=0

# ---------------------------------------------------------------------------
# Test helpers
# ---------------------------------------------------------------------------
setup_env() {
    # Create a temp directory with a mock java and a fake jenkins-cli.jar
    TMPDIR_TEST="$(mktemp -d)"

    # Mock java that prints its args so we can assert on the command line
    cat > "$TMPDIR_TEST/java" <<'MOCK'
#!/bin/bash
echo "MOCK_JAVA_CALL: $@"
exit 0
MOCK
    chmod +x "$TMPDIR_TEST/java"

    # Fake jenkins-cli.jar (just needs to exist for -f check)
    touch "$TMPDIR_TEST/jenkins-cli.jar"

    # Prepend mock dir to PATH so our fake java is picked up
    export PATH="$TMPDIR_TEST:$PATH"
    export JENKINS_URL="https://jenkins.example.com"
    export JENKINS_USERNAME="admin"
    export JENKINS_TOKEN="testtoken123"
    export JENKINS_CLI_JAR="$TMPDIR_TEST/jenkins-cli.jar"
}

teardown_env() {
    [[ -n "${TMPDIR_TEST:-}" && -d "$TMPDIR_TEST" ]] && rm -rf "$TMPDIR_TEST"
    unset JENKINS_URL JENKINS_USERNAME JENKINS_TOKEN JENKINS_CLI_JAR
}

assert_contains() {
    local output="$1" needle="$2" label="$3"
    if echo "$output" | grep -qF -- "$needle"; then
        echo "  [PASS] $label"
        (( PASS++ ))
    else
        echo "  [FAIL] $label  -- expected to find '$needle' in output"
        (( FAIL++ ))
    fi
}

assert_not_contains() {
    local output="$1" needle="$2" label="$3"
    if echo "$output" | grep -qF -- "$needle"; then
        echo "  [FAIL] $label  -- did NOT expect to find '$needle' in output"
        (( FAIL++ ))
    else
        echo "  [PASS] $label"
        (( PASS++ ))
    fi
}

assert_exit_code() {
    local actual="$1" expected="$2" label="$3"
    if [[ "$actual" -eq "$expected" ]]; then
        echo "  [PASS] $label (exit=$actual)"
        (( PASS++ ))
    else
        echo "  [FAIL] $label  -- expected exit=$expected, got exit=$actual"
        (( FAIL++ ))
    fi
}

run_script() {
    # Runs the script with given args, captures combined output and exit code.
    # Sets: SCRIPT_OUTPUT, SCRIPT_RC
    local tmp_out
    tmp_out="$(mktemp)"
    bash "$SCRIPT" "$@" > "$tmp_out" 2>&1
    SCRIPT_RC=$?
    SCRIPT_OUTPUT="$(cat "$tmp_out")"
    rm -f "$tmp_out"
}

# ---------------------------------------------------------------------------
# Test cases
# ---------------------------------------------------------------------------

echo "=== Test Suite: JenkinsJobsAutomation.sh ==="
echo

# ---- T1: --help exits cleanly ----
echo "[T1] --help prints usage and exits 0"
run_script --help
assert_exit_code "$SCRIPT_RC" 0 "--help exit code"
assert_contains "$SCRIPT_OUTPUT" "Usage:" "--help shows Usage"
assert_contains "$SCRIPT_OUTPUT" "--action" "--help mentions --action"
echo

# ---- T2: Missing connection info (no env, no args) ----
echo "[T2] Missing connection info produces clear errors"
(
    unset JENKINS_URL JENKINS_USERNAME JENKINS_TOKEN JENKINS_CLI_JAR
    run_script --action list
    assert_exit_code "$SCRIPT_RC" 1 "exit code 1 when connection info missing"
    assert_contains "$SCRIPT_OUTPUT" "Missing Jenkins connection information" "error header present"
    assert_contains "$SCRIPT_OUTPUT" "Jenkins URL" "mentions missing URL"
    assert_contains "$SCRIPT_OUTPUT" "Jenkins username" "mentions missing username"
    assert_contains "$SCRIPT_OUTPUT" "Jenkins token" "mentions missing token"
)
echo

# ---- T3: Missing jenkins-cli.jar ----
echo "[T3] Missing jenkins-cli.jar produces clear error"
(
    unset JENKINS_CLI_JAR
    export JENKINS_URL="https://jenkins.example.com"
    export JENKINS_USERNAME="admin"
    export JENKINS_TOKEN="testtoken"
    export JENKINS_CLI_JAR="/nonexistent/path/jenkins-cli.jar"
    run_script --action list
    assert_exit_code "$SCRIPT_RC" 1 "exit code 1 when jar missing"
    assert_contains "$SCRIPT_OUTPUT" "jenkins-cli.jar not found" "jar-not-found error"
)
echo

# ---- T4: Action requiring job name but no job given ----
echo "[T4] build without --job produces error"
setup_env
run_script --action build
assert_exit_code "$SCRIPT_RC" 1 "exit code 1 when job name missing for build"
assert_contains "$SCRIPT_OUTPUT" "requires a job name" "job-name-required error"
teardown_env
echo

echo "[T4b] delete without --job produces error"
setup_env
run_script --action delete
assert_exit_code "$SCRIPT_RC" 1 "exit code 1 when job name missing for delete"
assert_contains "$SCRIPT_OUTPUT" "requires a job name" "job-name-required error for delete"
teardown_env
echo

echo "[T4c] disable without --job produces error"
setup_env
run_script --action disable
assert_exit_code "$SCRIPT_RC" 1 "exit code 1 when job name missing for disable"
assert_contains "$SCRIPT_OUTPUT" "requires a job name" "job-name-required error for disable"
teardown_env
echo

# ---- T5: list does NOT require a job name ----
echo "[T5] list action succeeds without --job"
setup_env
run_script --action list
assert_exit_code "$SCRIPT_RC" 0 "exit code 0 for list without job"
assert_contains "$SCRIPT_OUTPUT" "Listing all jobs" "list action header"
assert_contains "$SCRIPT_OUTPUT" "MOCK_JAVA_CALL" "java was called"
assert_contains "$SCRIPT_OUTPUT" "list-jobs" "list-jobs subcommand used"
assert_contains "$SCRIPT_OUTPUT" "SUCCESS" "summary shows success"
teardown_env
echo

# ---- T6: Non-interactive build with --job ----
echo "[T6] Non-interactive build with --job"
setup_env
run_script --action build --job my-pipeline
assert_exit_code "$SCRIPT_RC" 0 "exit code 0 for build with job"
assert_contains "$SCRIPT_OUTPUT" "Building job 'my-pipeline'" "build header"
assert_contains "$SCRIPT_OUTPUT" "build -v -s my-pipeline" "correct build subcommand"
assert_contains "$SCRIPT_OUTPUT" "SUCCESS" "summary shows success"
teardown_env
echo

# ---- T7: Command concatenation is correct for all actions ----
echo "[T7] Command concatenation correctness"
for tc in "delete:delete-job testjob" "disable:disable-job testjob" "enable:enable-job testjob" "reload:reload-job testjob"; do
    action="${tc%%:*}"
    expected_sub="${tc#*:}"
    setup_env
    run_script --action "$action" --job testjob
    assert_exit_code "$SCRIPT_RC" 0 "exit code 0 for $action"
    assert_contains "$SCRIPT_OUTPUT" "$expected_sub" "subcommand '$expected_sub' in java call for $action"
    # Verify common parts
    assert_contains "$SCRIPT_OUTPUT" "-s https://jenkins.example.com" "URL in command for $action"
    assert_contains "$SCRIPT_OUTPUT" "-auth admin:testtoken123" "auth in command for $action"
    assert_contains "$SCRIPT_OUTPUT" "-webSocket" "webSocket flag in command for $action"
    teardown_env
done
echo

# ---- T8: Result summary content ----
echo "[T8] Result summary includes all required fields"
setup_env
run_script --action enable --job some-job
assert_contains "$SCRIPT_OUTPUT" "Result Summary" "summary header"
assert_contains "$SCRIPT_OUTPUT" "Action : enable" "summary has action"
assert_contains "$SCRIPT_OUTPUT" "Job    : some-job" "summary has job"
assert_contains "$SCRIPT_OUTPUT" "Target : https://jenkins.example.com" "summary has target URL"
assert_contains "$SCRIPT_OUTPUT" "Status : SUCCESS" "summary has success status"
teardown_env
echo

# ---- T9: Invalid action produces error ----
echo "[T9] Invalid action produces error"
setup_env
run_script --action bogus --job foo
assert_exit_code "$SCRIPT_RC" 1 "exit code 1 for invalid action"
assert_contains "$SCRIPT_OUTPUT" "Invalid action" "invalid action error"
teardown_env
echo

# ---- T10: Env-var based configuration works ----
echo "[T10] Env-var configuration is picked up"
setup_env
run_script --action list
assert_contains "$SCRIPT_OUTPUT" "https://jenkins.example.com" "URL from env used"
assert_contains "$SCRIPT_OUTPUT" "admin:testtoken123" "credentials from env used"
teardown_env
echo

# ---- T11: CLI args override env vars ----
echo "[T11] CLI args override env vars"
setup_env
run_script --action list --url https://other.example.com --username bob --token secret99
assert_contains "$SCRIPT_OUTPUT" "https://other.example.com" "overridden URL used"
assert_contains "$SCRIPT_OUTPUT" "bob:secret99" "overridden credentials used"
assert_not_contains "$SCRIPT_OUTPUT" "admin:testtoken123" "env credentials NOT used when CLI args given"
teardown_env
echo

# ---- T12: Interactive mode entry (simulated via stdin) ----
echo "[T12] Interactive mode: choosing 'list' (option 1)"
setup_env
# Feed choice "1" (list) to stdin
SCRIPT_OUTPUT="$(echo "1" | bash "$SCRIPT" 2>&1)"
SCRIPT_RC=$?
assert_exit_code "$SCRIPT_RC" 0 "interactive list exits 0"
assert_contains "$SCRIPT_OUTPUT" "Select a Choice" "menu is shown"
assert_contains "$SCRIPT_OUTPUT" "Listing all jobs" "list action runs"
assert_contains "$SCRIPT_OUTPUT" "Result Summary" "summary printed in interactive mode"
teardown_env
echo

echo "[T12b] Interactive mode: choosing 'build' (option 2) with job name"
setup_env
# Feed choice "2" then job name "myjob"
SCRIPT_OUTPUT="$(printf '2\nmyjob\n' | bash "$SCRIPT" 2>&1)"
SCRIPT_RC=$?
assert_exit_code "$SCRIPT_RC" 0 "interactive build exits 0"
assert_contains "$SCRIPT_OUTPUT" "Building job 'myjob'" "build action runs with prompted job"
assert_contains "$SCRIPT_OUTPUT" "Result Summary" "summary printed"
teardown_env
echo

echo "[T12c] Interactive mode: invalid choice"
setup_env
SCRIPT_OUTPUT="$(echo "9" | bash "$SCRIPT" 2>&1)"
SCRIPT_RC=$?
assert_exit_code "$SCRIPT_RC" 1 "invalid choice exits 1"
assert_contains "$SCRIPT_OUTPUT" "valid choice" "invalid choice error shown"
teardown_env
echo

# ---- T13: Unknown CLI option ----
echo "[T13] Unknown CLI option produces error"
setup_env
run_script --bogus
assert_exit_code "$SCRIPT_RC" 1 "exit code 1 for unknown option"
assert_contains "$SCRIPT_OUTPUT" "Unknown option" "unknown option error"
teardown_env
echo

# ---- T14: Failed java call produces FAILED summary ----
echo "[T14] Failed java call shows FAILED in summary"
(
    TMPDIR_FAIL="$(mktemp -d)"
    cat > "$TMPDIR_FAIL/java" <<'MOCK'
#!/bin/bash
echo "MOCK_JAVA_CALL: $@"
exit 42
MOCK
    chmod +x "$TMPDIR_FAIL/java"
    touch "$TMPDIR_FAIL/jenkins-cli.jar"
    export PATH="$TMPDIR_FAIL:$PATH"
    export JENKINS_URL="https://jenkins.example.com"
    export JENKINS_USERNAME="admin"
    export JENKINS_TOKEN="tok"
    export JENKINS_CLI_JAR="$TMPDIR_FAIL/jenkins-cli.jar"

    tmp_out="$(mktemp)"
    bash "$SCRIPT" --action list > "$tmp_out" 2>&1
    local_rc=$?
    local_output="$(cat "$tmp_out")"
    rm -f "$tmp_out"

    assert_contains "$local_output" "FAILED" "summary shows FAILED"
    assert_contains "$local_output" "exit code 42" "summary shows exit code"
    rm -rf "$TMPDIR_FAIL"
)
echo

# ---------------------------------------------------------------------------
# Final report
# ---------------------------------------------------------------------------
TOTAL=$(( PASS + FAIL ))
echo "======================================"
echo "  Total : $TOTAL"
echo "  Pass  : $PASS"
echo "  Fail  : $FAIL"
echo "======================================"

if [[ "$FAIL" -gt 0 ]]; then
    exit 1
fi
exit 0
