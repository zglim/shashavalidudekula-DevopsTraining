#!/bin/bash
#Purpose: Bash Scripting Training
#Author: Shashavali (original), refactored for CLI/env config support
#Date:  19th July,2022
#Use: Script for automating actions on Jenkins jobs.
#     Supports interactive menu and non-interactive CLI usage.

set -euo pipefail

##############################################################################
# Defaults — overridden by environment variables, then by CLI parameters
##############################################################################
JENKINS_URL="${JENKINS_URL:-}"
JENKINS_USERNAME="${JENKINS_USERNAME:-}"
JENKINS_TOKEN="${JENKINS_TOKEN:-}"
JENKINS_CLI_JAR="${JENKINS_CLI_JAR:-jenkins-cli.jar}"

ACTION=""
JOB_NAME=""

##############################################################################
# Help
##############################################################################
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --url   URL      Jenkins server URL        (env: JENKINS_URL)
  --user  USER     Jenkins username           (env: JENKINS_USERNAME)
  --token TOKEN    Jenkins API token          (env: JENKINS_TOKEN)
  --jar   PATH     Path to jenkins-cli.jar    (env: JENKINS_CLI_JAR, default: jenkins-cli.jar)
  --action ACTION  Action to perform: list, build, delete, disable, enable, reload
  --job   NAME     Job name (required for build/delete/disable/enable/reload)
  -h, --help       Show this help message

When --action is omitted the interactive menu is shown.

Examples:
  # Interactive menu, config via environment
  export JENKINS_URL=http://localhost:8080
  export JENKINS_USERNAME=admin
  export JENKINS_TOKEN=secret
  $(basename "$0")

  # Non-interactive list
  $(basename "$0") --url http://localhost:8080 --user admin --token secret --action list

  # Non-interactive build
  $(basename "$0") --action build --job my-pipeline
EOF
}

##############################################################################
# Parse CLI arguments (override env vars)
##############################################################################
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --url)    JENKINS_URL="$2";      shift 2 ;;
            --user)   JENKINS_USERNAME="$2";  shift 2 ;;
            --token)  JENKINS_TOKEN="$2";     shift 2 ;;
            --jar)    JENKINS_CLI_JAR="$2";   shift 2 ;;
            --action) ACTION="$2";            shift 2 ;;
            --job)    JOB_NAME="$2";          shift 2 ;;
            -h|--help) usage; exit 0 ;;
            *)
                echo "Error: Unknown option '$1'" >&2
                usage >&2
                exit 1
                ;;
        esac
    done
}

##############################################################################
# Validation helpers
##############################################################################
validate_connection() {
    local errors=0
    if [[ -z "$JENKINS_URL" ]]; then
        echo "Error: Jenkins URL is not set. Use --url or export JENKINS_URL." >&2
        errors=$((errors + 1))
    fi
    if [[ -z "$JENKINS_USERNAME" ]]; then
        echo "Error: Jenkins username is not set. Use --user or export JENKINS_USERNAME." >&2
        errors=$((errors + 1))
    fi
    if [[ -z "$JENKINS_TOKEN" ]]; then
        echo "Error: Jenkins token is not set. Use --token or export JENKINS_TOKEN." >&2
        errors=$((errors + 1))
    fi
    if [[ ! -f "$JENKINS_CLI_JAR" ]]; then
        echo "Error: jenkins-cli.jar not found at '$JENKINS_CLI_JAR'. Use --jar or export JENKINS_CLI_JAR." >&2
        errors=$((errors + 1))
    fi
    if [[ $errors -gt 0 ]]; then
        return 1
    fi
}

# Actions that require a job name
ACTION_NEEDS_JOB="build delete disable enable reload"

validate_job_name() {
    local action="$1"
    # Check whether this action requires a job name
    for a in $ACTION_NEEDS_JOB; do
        if [[ "$a" == "$action" ]]; then
            if [[ -z "$JOB_NAME" ]]; then
                echo "Error: Action '$action' requires a job name. Use --job or enter it when prompted." >&2
                return 1
            fi
            return 0
        fi
    done
    return 0
}

##############################################################################
# Core Jenkins CLI wrapper
##############################################################################
run_jenkins_cli() {
    # $@ = Jenkins CLI sub-command and its arguments
    java -jar "$JENKINS_CLI_JAR" \
         -s "$JENKINS_URL" \
         -auth "$JENKINS_USERNAME:$JENKINS_TOKEN" \
         -webSocket \
         "$@"
}

##############################################################################
# Result summary
##############################################################################
print_summary() {
    local action="$1"
    local job="${2:-}"
    local exit_code="$3"

    echo
    echo "========== Result Summary =========="
    echo "  Action : $action"
    if [[ -n "$job" ]]; then
        echo "  Job    : $job"
    fi
    echo "  Server : $JENKINS_URL"
    if [[ "$exit_code" -eq 0 ]]; then
        echo "  Status : SUCCESS"
    else
        echo "  Status : FAILED (exit code $exit_code)"
    fi
    echo "===================================="
}

##############################################################################
# Execute a single action
##############################################################################
execute_action() {
    local action="$1"
    local rc=0

    case "$action" in
        list)
            echo
            echo "Listing all jobs"
            echo "----------------"
            run_jenkins_cli list-jobs || rc=$?
            print_summary "list" "" "$rc"
            ;;
        build)
            echo
            echo "Building job $JOB_NAME"
            echo "----------------------"
            run_jenkins_cli build -v -s "$JOB_NAME" || rc=$?
            print_summary "build" "$JOB_NAME" "$rc"
            ;;
        delete)
            echo
            echo "Deleting job $JOB_NAME"
            echo "----------------------"
            run_jenkins_cli delete-job "$JOB_NAME" || rc=$?
            print_summary "delete" "$JOB_NAME" "$rc"
            ;;
        disable)
            echo
            echo "Disabling job $JOB_NAME"
            echo "----------------------"
            run_jenkins_cli disable-job "$JOB_NAME" || rc=$?
            print_summary "disable" "$JOB_NAME" "$rc"
            ;;
        enable)
            echo
            echo "Enabling job $JOB_NAME"
            echo "----------------------"
            run_jenkins_cli enable-job "$JOB_NAME" || rc=$?
            print_summary "enable" "$JOB_NAME" "$rc"
            ;;
        reload)
            echo
            echo "Reloading the job $JOB_NAME"
            echo "----------------------"
            run_jenkins_cli reload-job "$JOB_NAME" || rc=$?
            print_summary "reload" "$JOB_NAME" "$rc"
            ;;
        *)
            echo "Error: Unknown action '$action'. Valid actions: list, build, delete, disable, enable, reload." >&2
            return 1
            ;;
    esac

    return "$rc"
}

##############################################################################
# Interactive menu
##############################################################################
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

    case $choice in
        1) ACTION="list"    ;;
        2) ACTION="build"   ;;
        3) ACTION="delete"  ;;
        4) ACTION="disable" ;;
        5) ACTION="enable"  ;;
        6) ACTION="reload"  ;;
        *)
            echo "Please select a valid choice" >&2
            exit 1
            ;;
    esac

    # Prompt for job name if the selected action requires one
    for a in $ACTION_NEEDS_JOB; do
        if [[ "$a" == "$ACTION" && -z "$JOB_NAME" ]]; then
            echo "Enter the name of the job:"
            read -r JOB_NAME
            echo
            break
        fi
    done
}

##############################################################################
# Main
##############################################################################
main() {
    parse_args "$@"

    # If no action specified, fall back to interactive menu
    if [[ -z "$ACTION" ]]; then
        interactive_menu
    fi

    # Validate connection info and jar
    if ! validate_connection; then
        exit 1
    fi

    # Validate job name for actions that require it
    if ! validate_job_name "$ACTION"; then
        exit 1
    fi

    execute_action "$ACTION"
}

# Only run main when executed directly (not when sourced for testing)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
