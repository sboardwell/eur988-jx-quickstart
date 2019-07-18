#!/usr/bin/env bash

set -euo pipefail

function die() { echo "$@" 1>&2 ; exit 1; }

function dieGracefully() { echo "$@" 1>&2 ; exit 0; }

function confirm () {
    # call with a prompt string or use a default
    local default_answer='Y'
    read -p "${1:-Are you sure?} [Y/n]" default_answer_input
    default_answer=${default_answer_input:-$default_answer}
    #[ -n "$REPLY" ] && echo    # (optional) move to a new line
    if [[ $default_answer =~ ^[Nn]$ ]]; then
        dieGracefully "Received '${default_answer:-N}'. ${2:-Exiting gracefully}."
    elif [[ ! $default_answer =~ ^[Yy]$ ]]; then
        die "Did not recognise answer '${default_answer:-N}'."
    fi
}

# This method will look for in order of priority
#
#  - a "version.json" file (created by another container in the CI build scenario)
#  - the necessary binaries
#  - a running docker process to replace the binaries
#
function prereqs() {
  ROOT="$(git rev-parse --show-toplevel)"
  OS=$(uname | tr '[:upper:]' '[:lower:]')
  if [ -r "${ROOT}/version.json" ]; then
    GITVERSION_CMD="cat ${ROOT}/version.json"
  elif gitversion -h &> /dev/null; then
    GITVERSION_CMD="gitversion"
  elif docker info &> /dev/null; then
    GITVERSION_CMD="docker run --rm -v ${ROOT}:/repo gittools/gitversion:5.0.0-linux /repo"
  else
    die "No gitversion and no docker "
  fi
  if jq -h &> /dev/null; then
    JQ_CMD="jq"
  elif docker info &> /dev/null; then
    JQ_CMD="docker run -i --rm diversario/eks-tools:0.0.3 jq"
  else
    die "No gitversion and no docker "
  fi
}

function run_cmd() {
  prereqs
  ${GITVERSION_CMD} $@
}

# use it method to get a particular field from the returned JSON string
function get_field() {
  prereqs
  if [ -n "${1:-}" ]; then
    ${GITVERSION_CMD} | ${JQ_CMD} -r .${1}
  else
    ${GITVERSION_CMD}
  fi
}

function ensure_pristine_workspace() {
  local git_status
  git_status=$(git status -s)
  original_branch=$(git symbolic-ref --short HEAD)
  #[ -z "$git_status" ]  || { echo -e "Changes found:\n$git_status\n"; die "Workspace must be free of changes. See above and please correct."; }
}

function ensure_single_branch() {
  local pattern=$1
  local branches
  branches=$(git ls-remote --quiet origin "$pattern" | sed 's:.*/::g')
  [ -n "$branches" ] || die "Remote branch(es) matching '$pattern' DOES NOT exist."
  (( $(grep -c . <<< "$branches") == 1 )) || { echo -e "Branches found:\n$branches"; die "Zero or multiple remote branches matching pattern '$pattern'. See above."; }
  [ -z "${2:-}" ] || echo $branches
}

function ensure_no_branch() {
  local pattern=$1
  local branches
  branches=$(git ls-remote --quiet origin "$pattern" | sed 's:.*/::g')
  [ -z "$branches" ] || { echo -e "Branches found:\n$branches"; die "Remote branch(es) matching '$pattern' ALREADY exist. See above."; }
}

function checkout_branch() {
  local branch=$1
  git checkout $branch
  git pull origin $branch
}

function create_branch() {
  local sourceBranch=$1
  local targetBranch=$2
  read -p "Source branch [$sourceBranch]: " sourceBranchInput
  sourceBranch=${sourceBranchInput:-$sourceBranch}
  read -p "Target branch [$targetBranch]: " targetBranchInput
  targetBranch=${targetBranchInput:-$targetBranch}
  confirm "Create branch '$targetBranch' from source '$sourceBranch'"
  git checkout -b $targetBranch
  git push --set-upstream origin $targetBranch
}

function merge_source_into_target() {
  local source=$1
  local target=$2
  confirm "Will merge release '$source' into '$target'"
  checkout_branch $source
  checkout_branch $target
  git merge $source
  git push origin $target
}

function delete_branch() {
  local branch=$1
  confirm "Will delete branch '$branch' both locally and remote."
  git branch -d $branch
  git push origin :$branch
}

function create_release() {
  local targetVersion
  ensure_single_branch "$GF_DEVELOP"
  ensure_no_branch "$GF_RELEASE_PATTERN"
  targetVersion=$(run_cmd /showvariable MajorMinorPatch)
  create_branch "$GF_DEVELOP" "release-${targetVersion}"
}

function create_hotfix() {
  local major minor patch targetVersion
  ensure_single_branch "$GF_MASTER"
  ensure_no_branch "$GF_HOTFIX_PATTERN"
  git checkout "$GF_MASTER" -q
  major=$(run_cmd /showvariable Major)
  minor=$(run_cmd /showvariable Minor)
  patch=$(run_cmd /showvariable Patch)
  targetVersion="${major}.${minor}.$(( $patch + 1 ))"
  create_branch "$GF_MASTER" "hotfix-${targetVersion}"
}

function merge_release() {
  local masterBr developBr workingBr
  masterBr=$(ensure_single_branch "$GF_MASTER" true)
  developBr=$(ensure_single_branch "$GF_DEVELOP" true)
  workingBr=$(ensure_single_branch "$GF_RELEASE_PATTERN" true)
  merge_source_into_target $workingBr $developBr
  merge_source_into_target $workingBr $masterBr
  delete_branch $workingBr
  tag_branch "$GF_MASTER"
}

function merge_hotfix() {
  local masterBr workingBr
  masterBr=$(ensure_single_branch "$GF_MASTER" true)
  workingBr=$(ensure_single_branch "$GF_HOTFIX_PATTERN" true)
  merge_source_into_target $workingBr $masterBr
  delete_branch $workingBr
  tag_branch "$GF_MASTER"
}

function tag_branch() {
  local workingBr=$1
  local tag
  workingBr=$(ensure_single_branch "$workingBr" true)
  checkout_branch $workingBr
  tag="v$(run_cmd /showvariable SemVer)"
  confirm "Will tag branch '$workingBr' with '$tag'"
  git tag -am "Add tag '$tag' (performed by $USER)" $tag
  git push origin $tag
}

function finish {
  if [ -n "${original_branch:-}" ]; then
    echo "Returning to original branch '$original_branch'."
    git checkout $original_branch -q
  fi
}
trap finish EXIT

ARG=${1:-}; shift || true

# some default vars - need to change them for europa.
GF_MASTER="master"
GF_DEVELOP='develop'
GF_RELEASE_PATTERN='release-*'
GF_HOTFIX_PATTERN='hotfix-*'

if [[ $ARG == 'prereqs' ]]; then
  prereqs
elif [[ $ARG == 'run' ]]; then
  run_cmd $@
elif [[ $ARG == 'f' ]]; then
  get_field ${1:-}
elif [[ $ARG == 'create_release' ]]; then
  ensure_pristine_workspace
  create_release $@
elif [[ $ARG == 'tag_release' ]]; then
  ensure_pristine_workspace
  tag_branch "$GF_RELEASE_PATTERN" $@
elif [[ $ARG == 'tag_master' ]]; then
  ensure_pristine_workspace
  tag_branch "$GF_MASTER" $@
elif [[ $ARG == 'create_hotfix' ]]; then
  ensure_pristine_workspace
  create_hotfix $@
elif [[ $ARG == 'merge_release' ]]; then
  ensure_pristine_workspace
  merge_release $@
elif [[ $ARG == 'merge_hotfix' ]]; then
  ensure_pristine_workspace
  merge_hotfix $@
else
  die "method '$ARG' not found"
fi
