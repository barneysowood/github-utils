#!/usr/bin/env bash

# Script to look up a GitHub user and provide a summary

# Enable strict mode
set -o errexit
set -o nounset
set -o pipefail

# Default values
JSON_OUTPUT=false

# Functions
usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] <username>

Provides a summary of a GitHub user.

OPTIONS:
  -h, --help     Show this help message and exit
  -j, --json     Output information in JSON format

ARGUMENTS:
  username       GitHub username to look up (required)
EOF
  exit "${1:-0}"
}

error() {
  local message="$1"
  local exit_code="${2:-1}"
  echo "ERROR: $message" >&2
  exit "$exit_code"
}

check_dependencies() {
  if ! command -v gh &> /dev/null; then
    error "GitHub CLI (gh) is not installed. Please install it first." 2
  fi
  
  # Check if user is authenticated with gh
  if ! gh auth status &> /dev/null; then
    error "Not authenticated with GitHub CLI. Please run 'gh auth login' first." 3
  fi
}

get_user_summary() {
  local username="$1"
  local temp_file
  temp_file=$(mktemp)
  
  # Fetch user information using gh api
  if ! gh api "users/$username" > "$temp_file" 2>/dev/null; then
    rm -f "$temp_file"
    error "Failed to fetch information for user '$username'. User may not exist." 4
  fi
  
  if [[ "$JSON_OUTPUT" == true ]]; then
    # For JSON output, just output the API response directly
    cat "$temp_file"
  else
    # Extract user information
    local name
    local created_at
    local followers
    local following
    local public_repos
    local bio
    local location
    local company
    
    name=$(jq -r '.name // "N/A"' "$temp_file")
    created_at=$(jq -r '.created_at' "$temp_file" | cut -d'T' -f1)
    followers=$(jq -r '.followers' "$temp_file")
    following=$(jq -r '.following' "$temp_file")
    public_repos=$(jq -r '.public_repos' "$temp_file")
    bio=$(jq -r '.bio // "N/A"' "$temp_file")
    location=$(jq -r '.location // "N/A"' "$temp_file")
    company=$(jq -r '.company // "N/A"' "$temp_file")
    
    # Output summary
    cat <<EOF
GitHub User Summary: $username
-----------------
Name: $name
Created on: $created_at
Location: $location
Company: $company
Bio: $bio

Activity:
  Public repositories: $public_repos
  Followers: $followers
  Following: $following
EOF
  fi
  
  # Clean up temp file
  rm -f "$temp_file"
}

# Parse command line options
while getopts ":hj-:" opt; do
  case $opt in
    h)
      usage 0
      ;;
    j)
      JSON_OUTPUT=true
      ;;
    -)
      case "${OPTARG}" in
        help)
          usage 0
          ;;
        json)
          JSON_OUTPUT=true
          ;;
        *)
          echo "Unknown option: --${OPTARG}" >&2
          usage 1
          ;;
      esac
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      usage 1
      ;;
  esac
done

# Shift arguments to get positional parameters
shift $((OPTIND-1))

# Check if username is provided
if [[ $# -ne 1 ]]; then
  error "A GitHub username must be provided" 1
fi

USERNAME="$1"

# Main execution
check_dependencies
get_user_summary "$USERNAME"
