#!/bin/bash
# Purpose: Jenkins CLI automation tool with interactive menu and non-interactive CLI mode.
# Author: Shashavali (original); enhanced by code agent.
# Date:   19th July, 2022 (original); 2026-06-15 (enhanced).
# Use:    Automate common Jenkins job actions (list, build, delete, disable, enable, reload).
#
# Configuration can come from (in increasing priority order):
#   1. Environment variables: JENKINS_URL, JENKINS_USERNAME, JENKINS_TOKEN, JENKINS_CLI_JAR
#   2. Command-line arguments:  --url, --username, --token, --jar
# Non-interactive mode:
#   --action <list|build|delete|disable|enable|reload> [--job <jobName>]
# Interactive mode:
#   Run without --action to get the menu prompt.

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults / placeholders
# ---------------------------------------------------------------------------
jenkinsUrl="${JENKINS_URL:-}"
jenkinsUsername="${JENKINS_USERNAME:-}"
jenkinsToken="${JENKINS_TOKEN:-}"
jenkinsCliJar="${JENKINS_CLI_JAR:-jenkins-cli.jar}"

cliAction=""
cliJob=""
interactive=true

# ---------------------------------------------------------------------------
# Actions that require a job name
# ---------------------------------------------------------------------------
ACTIONS_NEEDING_JOB=("build" "delete" "disable" "enable" "reload")
ALL_ACTIONS=("list" "build" "delete" "disable" "enable" "reload")

# ---------------------------------------------------------------------------
# Usage / help
# ---------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Interactive mode (no --action given):
  Shows a menu to choose the operation and prompts for job name when needed.

Non-interactive mode:
  $(basename "$0") --action <action> [--job <jobName>] [connection options]

Actions:
  list       List all Jenkins jobs (no job name needed)
  build      Build a job (requires --job)
  delete     Delete a job (requires --job)
  disable    Disable a job (requires --job)
  enable     Enable a job (requires --job)
  reload     Reload a job (requires --job)

Connection options:
  --url <url>          Jenkins base URL          (or set JENKINS_URL)
  --username <user>    Jenkins username           (or set JENKINS_USERNAME)
  --token <token>      Jenkins API token          (or set JENKINS_TOKEN)
  --jar <path>         Path to jenkins-cli.jar    (or set JENKINS_CLI_JAR, default: jenkins-cli.jar)

General:
  -h, --help           Show this help message

Examples:
  # Interactive
  export JENKINS_URL=https://jenkins.example.com JENKINS_USERNAME=admin JENKINS_TOKEN=abc123
  $(basename "$0")

  # Non-interactive
  $(basename "$0") --url https://jenkins.example.com --username admin --token abc123 --action list
  $(basename "$0") --action build --job my-pipeline --url https://jenkins.example.com --username admin --token abc123
EOF
}

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
err()  { echo "[ERROR] $*" >&2; }
info() { echo "[INFO]  $*"; }

# ---------------------------------------------------------------------------
# Parse command-line arguments
# ---------------------------------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --url)
                [[ $# -ge 2 ]] || { err "Missing value for --url"; exit 1; }
                jenkinsUrl="$2"; shift 2 ;;
            --username)
                [[ $# -ge 2 ]] || { err "Missing value for --username"; exit 1; }
                jenkinsUsername="$2"; shift 2 ;;
            --token)
                [[ $# -ge 2 ]] || { err "Missing value for --token"; exit 1; }
                jenkinsToken="$2"; shift 2 ;;
            --jar)
                [[ $# -ge 2 ]] || { err "Missing value for --jar"; exit 1; }
                jenkinsCliJar="$2"; shift 2 ;;
            --action)
                [[ $# -ge 2 ]] || { err "Missing value for --action"; exit 1; }
                cliAction="$2"; interactive=false; shift 2 ;;
            --job)
                [[ $# -ge 2 ]] || { err "Missing value for --job"; exit 1; }
                cliJob="$2"; shift 2 ;;
            -h|--help)
                usage; exit 0 ;;
            *)
                err "Unknown option: $1"; usage; exit 1 ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------
validate_connection() {
    local missing=()
    [[ -n "$jenkinsUrl"      ]] || missing+=("Jenkins URL (--url / JENKINS_URL)")
    [[ -n "$jenkinsUsername" ]] || missing+=("Jenkins username (--username / JENKINS_USERNAME)")
    [[ -n "$jenkinsToken"    ]] || missing+=("Jenkins token (--token / JENKINS_TOKEN)")

    if [[ ${#missing[@]} -gt 0 ]]; then
        err "Missing Jenkins connection information:"
        for item in "${missing[@]}"; do
            err "  - $item"
        done
        return 1
    fi

    if [[ ! -f "$jenkinsCliJar" ]]; then
        err "jenkins-cli.jar not found at path: $jenkinsCliJar"
        err "Provide the correct path via --jar or JENKINS_CLI_JAR."
        return 1
    fi
}

validate_action() {
    local action="$1"
    local valid=false
    for a in "${ALL_ACTIONS[@]}"; do
        [[ "$action" == "$a" ]] && { valid=true; break; }
    done
    if [[ "$valid" == false ]]; then
        err "Invalid action: '$action'. Must be one of: ${ALL_ACTIONS[*]}"
        return 1
    fi
}

validate_job_name() {
    local action="$1"
    local job="$2"
    for a in "${ACTIONS_NEEDING_JOB[@]}"; do
        if [[ "$action" == "$a" && -z "$job" ]]; then
            err "Action '$action' requires a job name. Provide it via --job or interactively."
            return 1
        fi
    done
}

# ---------------------------------------------------------------------------
# Unified Jenkins CLI invocation
# ---------------------------------------------------------------------------
run_jenkins_cmd() {
    # Usage: run_jenkins_cmd <jenkins-cli-subcommand> [extra args...]
    local subcmd="$1"; shift

    java -jar "$jenkinsCliJar" \
         -s "$jenkinsUrl" \
         -auth "${jenkinsUsername}:${jenkinsToken}" \
         -webSocket \
         "$subcmd" \
         "$@"
}

# ---------------------------------------------------------------------------
# Action dispatchers
# ---------------------------------------------------------------------------
do_list() {
    info "Listing all jobs"
    echo "----------------"
    run_jenkins_cmd list-jobs
}

do_build() {
    local job="$1"
    info "Building job '$job'"
    echo "----------------------"
    run_jenkins_cmd build -v -s "$job"
}

do_delete() {
    local job="$1"
    info "Deleting job '$job'"
    echo "----------------------"
    run_jenkins_cmd delete-job "$job"
}

do_disable() {
    local job="$1"
    info "Disabling job '$job'"
    echo "----------------------"
    run_jenkins_cmd disable-job "$job"
}

do_enable() {
    local job="$1"
    info "Enabling job '$job'"
    echo "----------------------"
    run_jenkins_cmd enable-job "$job"
}

do_reload() {
    local job="$1"
    info "Reloading job '$job'"
    echo "----------------------"
    run_jenkins_cmd reload-job "$job"
}

# ---------------------------------------------------------------------------
# Execute an action (shared by interactive and non-interactive paths)
# Returns: 0 on success, 1 on failure
# ---------------------------------------------------------------------------
execute_action() {
    local action="$1"
    local job="$2"

    validate_action "$action" || return 1
    validate_job_name "$action" "$job" || return 1

    case "$action" in
        list)    do_list                        ;;
        build)   do_build   "$job"              ;;
        delete)  do_delete  "$job"              ;;
        disable) do_disable "$job"              ;;
        enable)  do_enable  "$job"              ;;
        reload)  do_reload  "$job"              ;;
        *)       err "Unexpected action: $action"; return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# Result summary
# ---------------------------------------------------------------------------
print_summary() {
    local action="$1"
    local job="$2"
    local rc="$3"

    echo
    echo "===== Result Summary ====="
    echo "  Action : $action"
    if [[ -n "$job" ]]; then
        echo "  Job    : $job"
    else
        echo "  Job    : (n/a)"
    fi
    echo "  Target : $jenkinsUrl"
    if [[ "$rc" -eq 0 ]]; then
        echo "  Status : SUCCESS"
    else
        echo "  Status : FAILED (exit code $rc)"
    fi
    echo "=========================="
}

# ---------------------------------------------------------------------------
# Interactive menu
# ---------------------------------------------------------------------------
interactive_menu() {
    echo "Select a Choice"
    echo "1 ==> List Jobs"
    echo "2 ==> Build Job"
    echo "3 ==> Delete Job"
    echo "4 ==> Disable Job"
    echo "5 ==> Enable Job"
    echo "6 ==> Reload Job"
    echo
    echo "Enter your choice: "
    read -r choice
    echo

    local action="" job=""
    case "$choice" in
        1) action="list"    ;;
        2) action="build"   ;;
        3) action="delete"  ;;
        4) action="disable" ;;
        5) action="enable"  ;;
        6) action="reload"  ;;
        *)
            err "Please select a valid choice (1-6)."
            return 1
            ;;
    esac

    # Prompt for job name when the action requires one
    for a in "${ACTIONS_NEEDING_JOB[@]}"; do
        if [[ "$action" == "$a" ]]; then
            echo "Enter the name of the job you want to ${action}: "
            read -r job
            echo
            break
        fi
    done

    execute_action "$action" "$job"
    local rc=$?
    print_summary "$action" "$job" "$rc"
    return $rc
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    parse_args "$@"

    # Validate connection info regardless of mode
    validate_connection || exit 1

    if [[ "$interactive" == true ]]; then
        interactive_menu
        exit $?
    fi

    # Non-interactive mode
    local rc=0
    execute_action "$cliAction" "$cliJob" || rc=$?
    print_summary "$cliAction" "$cliJob" "$rc"
    exit $rc
}

main "$@"
