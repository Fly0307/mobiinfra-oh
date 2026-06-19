#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/fetch_pr_merge.sh <pr-number> [safe-branch] [--remote origin]

Examples:
  scripts/fetch_pr_merge.sh 1
  scripts/fetch_pr_merge.sh 1 main
  scripts/fetch_pr_merge.sh 1 --safe-branch feh_dev --remote upstream
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
git_safe_dir="$repo_root"

remote="${REMOTE:-origin}"
safe_branch="feh_dev"
positional=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    -r|--remote)
      [[ $# -ge 2 ]] || die "--remote requires a value"
      remote="$2"
      shift 2
      ;;
    -b|--safe-branch)
      [[ $# -ge 2 ]] || die "--safe-branch requires a value"
      safe_branch="$2"
      shift 2
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do
        positional+=("$1")
        shift
      done
      ;;
    -*)
      die "unknown option: $1"
      ;;
    *)
      positional+=("$1")
      shift
      ;;
  esac
done

[[ ${#positional[@]} -ge 1 ]] || die "missing PR number"
[[ ${#positional[@]} -le 2 ]] || die "too many positional arguments"

pr_number="${positional[0]}"
if [[ ${#positional[@]} -eq 2 ]]; then
  safe_branch="${positional[1]}"
fi

[[ "$pr_number" =~ ^[1-9][0-9]*$ ]] || die "PR number must be a positive integer"

git_cmd() {
  git -c "safe.directory=$git_safe_dir" "$@"
}

cd "$repo_root"
if [[ "$(git_cmd rev-parse --is-inside-work-tree 2>/dev/null)" != "true" ]]; then
  die "this script must be run inside a git repository"
fi

target_branch="pr-${pr_number}-merge-test"
target_ref="refs/heads/$target_branch"
remote_merge_ref="pull/$pr_number/merge:$target_branch"
current_branch="$(git_cmd branch --show-current || true)"
target_exists=0
if git_cmd show-ref --verify --quiet "$target_ref"; then
  target_exists=1
fi

echo "PR number: $pr_number"
echo "Local branch: $target_branch"
echo "Remote ref: $remote/$remote_merge_ref"

if [[ "$target_exists" -eq 1 && "$current_branch" == "$target_branch" ]]; then
  [[ -n "$safe_branch" ]] || die "current branch is $target_branch; provide a safe branch first"
  echo "Current branch is $target_branch; checking out $safe_branch first..."
  git_cmd checkout "$safe_branch"
fi

if [[ "$target_exists" -eq 1 ]]; then
  echo "Deleting existing local branch $target_branch..."
  git_cmd branch -D "$target_branch"
fi

echo "Fetching latest PR merge ref..."
git_cmd fetch "$remote" "$remote_merge_ref"

echo "Checking out $target_branch..."
git_cmd checkout "$target_branch"

echo "Done. Now on $target_branch."
