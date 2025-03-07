#!/usr/bin/env bash

# gh-issues-delete.sh - A script to delete GitHub issues from specific users
# 
# Usage: gh-issues-delete.sh REPO USERNAME [-l] [-h]
#
# Arguments:
#   REPO         Repository in format 'owner/repo'
#   USERNAME     GitHub username to filter issues by
#
# Options:
#   -l           List issues only (don't prompt for deletion)
#   -h           Display this help message and exit

set -eo pipefail

# Function to display usage information
usage() {
    cat << EOF
Usage: $(basename "$0") REPO USERNAME [-l] [-h]

Arguments:
  REPO         Repository in format 'owner/repo'
  USERNAME     GitHub username to filter issues by

Options:
  -l           List issues only (don't prompt for deletion)
  -h           Display this help message and exit
EOF
    exit 1
}

# Function to check if gh command is installed
check_gh() {
    if ! command -v gh &> /dev/null; then
        echo "Error: GitHub CLI (gh) is not installed or not in PATH"
        echo "Please install it from: https://cli.github.com/"
        exit 1
    fi

    # Check if user is authenticated with gh
    if ! gh auth status &> /dev/null; then
        echo "Error: You are not authenticated with GitHub CLI"
        echo "Please run 'gh auth login' first"
        exit 1
    fi
}

# Function to run gh api command with error checking
gh_api() {
    local output
    local exit_code
    
    # Run the command and capture both output and exit code
    output=$(gh api "$@" 2>&1) || exit_code=$?
    
    # Check if the command failed
    if [[ -n "${exit_code}" ]]; then
        echo "Error executing GitHub API command: ${output}"
        return "${exit_code}"
    fi
    
    # Return the output
    echo "${output}"
    return 0
}

# Function to list issues by a specific user and return the issue numbers
list_issues() {
    local repo="$1"
    local username="$2"
    local temp_file="$3"
    local issues
    
    echo "Fetching issues from user '${username}' in repository '${repo}'..."
    
    # Use jq to format the output if available
    if command -v jq &> /dev/null; then
        if ! issues=$(gh_api "repos/${repo}/issues?state=all&creator=${username}&per_page=100"); then
            return 1
        fi
        
        if [[ $(echo "$issues" | jq length) -eq 0 ]]; then
            echo "No issues found for user '${username}' in repository '${repo}'"
            return 1
        fi
        
        echo -e "\nIssues by ${username}:"
        echo "$issues" | jq -r '.[] | "#\(.number) - \(.title) (\(.state))"'
        
        # Extract issue numbers
        echo "$issues" | jq -r '.[].number' > "$temp_file"
    else
        # Fallback if jq is not available
        if ! issues=$(gh issue list --repo "${repo}" --author "${username}" --state all --json number,title,state); then
            echo "Error fetching issues from GitHub"
            return 1
        fi
        
        if [[ "$issues" == "[]" || -z "$issues" ]]; then
            echo "No issues found for user '${username}' in repository '${repo}'"
            return 1
        fi
        
        echo -e "\nIssues by ${username}:"
        gh issue list --repo "${repo}" --author "${username}" --state all --json number,title,state \
            --template '{{range .}}#{{.number}} - {{.title}} ({{.state}}){{"\n"}}{{end}}'
        
        # Extract issue numbers
        gh issue list --repo "${repo}" --author "${username}" --state all --json number \
            --template '{{range .}}{{.number}}{{"\n"}}{{end}}' > "$temp_file"
    fi
    
    # Count and display number of issues found
    local issue_count
    issue_count=$(grep -c '^' "$temp_file" || echo 0)
    echo -e "\nFound ${issue_count} issues by ${username}"
    
    return 0
}

# Function to delete issues using GraphQL API
delete_issues() {
    local repo="$1"
    local username="$2"
    local temp_file="$3"
    
    # Parse owner and repo name
    local owner="${repo%%/*}"
    local repo_name="${repo##*/}"
    
    local total
    total=$(grep -c '^' "$temp_file" || echo 0)
    local counter=0
    local failed=0
    local response
    local delete_response
    
    echo -e "\nDeleting issues..."
    
    while IFS= read -r issue_number; do
        counter=$((counter + 1))
        echo -ne "Processing issue #${issue_number} (${counter}/${total})\r"
        
        # Step 1: Get the global node ID for the issue using GraphQL
        local query="query { repository(owner: \"${owner}\", name: \"${repo_name}\") { issue(number: ${issue_number}) { id } } }"
        
        if ! response=$(gh api graphql -f query="${query}" 2>&1); then
            echo -e "\nFailed to get node ID for issue #${issue_number}: ${response}"
            failed=$((failed + 1))
            continue
        fi
        
        # Extract the global node ID using either jq or grep/sed
        local issue_id
        if command -v jq &> /dev/null; then
            issue_id=$(echo "$response" | jq -r '.data.repository.issue.id')
        else
            issue_id=$(echo "$response" | grep -o '"id":"[^"]*"' | head -1 | sed 's/"id":"//;s/"//')
        fi
        
        if [[ -z "$issue_id" || "$issue_id" == "null" ]]; then
            echo -e "\nFailed to extract node ID for issue #${issue_number}"
            failed=$((failed + 1))
            continue
        fi
        
        # Step 2: Delete the issue using the global node ID
        local mutation="mutation { deleteIssue(input: {issueId: \"${issue_id}\" }) { repository { id } } }"
        
        if ! delete_response=$(gh api graphql -f query="${mutation}" 2>&1); then
            echo -e "\nFailed to delete issue #${issue_number}: ${delete_response}"
            failed=$((failed + 1))
            continue
        fi
        
        echo -e "\nSuccessfully deleted issue #${issue_number}"
        
        # Add a delay to avoid rate limiting
        sleep 0.5
    done < "$temp_file"
    
    echo -e "\nDeleted $((counter - failed))/${total} issues from user '${username}'"
    if [[ $failed -gt 0 ]]; then
        echo "Failed to delete ${failed} issues. You may need admin permissions for this repository."
    fi
}

# Parse command-line options
list_only=false

# Process options
while getopts "lh" opt; do
    case $opt in
        l)
            list_only=true
            ;;
        h)
            usage
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            usage
            ;;
    esac
done

# Shift past the options
shift $((OPTIND - 1))

# Check for the required positional arguments
if [[ $# -lt 2 ]]; then
    echo "Error: Repository and username are required arguments"
    usage
fi

repo="$1"
username="$2"

# Check if repo format is valid (owner/repo)
if ! [[ "$repo" =~ ^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$ ]]; then
    echo "Error: Repository must be in the format 'owner/repo'"
    exit 1
fi

# Check if gh command is installed and authenticated
check_gh

# Create a temporary file using mktemp
if ! command -v mktemp &> /dev/null; then
    echo "Error: mktemp command is not available"
    exit 1
fi

temp_file=$(mktemp -t gh-issues.XXXXXX)

# Make sure the temp file is removed on exit
trap 'rm -f "$temp_file"' EXIT

# List issues and store issue numbers in the temp file
if ! list_issues "$repo" "$username" "$temp_file"; then
    exit 0
fi

# Check if any issues were found
if [[ ! -s "$temp_file" ]]; then
    echo "No issues to process"
    exit 0
fi

# Exit if list_only flag is set
if $list_only; then
    exit 0
fi

# Prompt for confirmation before deletion
read -r -p "Do you want to delete these issues? (y/N): " confirm
if [[ "$confirm" =~ ^[Yy]$ ]]; then
    delete_issues "$repo" "$username" "$temp_file"
else
    echo "Operation cancelled"
    exit 0
fi
