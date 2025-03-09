# Github utils

Some scripts and utils I use for interacting with Github.

## Requirements

* [Github CLI](https://cli.github.com/)
* [jq](https://jqlang.org/)

## Scripts

### Delete issues

[gh-issues-delete.sh](scripts/gh-issues-delete.sh) - will list issues created by a user in the specified repository and ask if you want to delete them. Useful for bulk deleting spam issues.

**WARNING** - this will permanently delete issues, use with care.

### User summary

[gh-user-summary.sh](scripts/gh-user-summary.sh) - get summary info on a Github user. Useful for checking if a user look legitimate.
