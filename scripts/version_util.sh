#!/usr/bin/env bash

set -euo pipefail

die() { echo "$@" 1>&2 ; exit 1; }

dieGracefully() { echo "$@" 1>&2 ; exit 0; }

confirm () {
    # call with a prompt string or use a default
    read -p "${1:-Are you sure?} [y/N]" -n 1 -r
    [ -n "$REPLY" ] && echo    # (optional) move to a new line
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        dieGracefully "Received '${REPLY:-N}'. ${2:-Exiting gracefully}."
    fi
}

# This method will look for in order of priority
#
#  - a "version.json" file (created by another container in the CI build scenario)
#  - the necessary binaries
#  - a running docker process to replace the binaries
#
prereqs() {
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

run_cmd() {
  prereqs
  ${GITVERSION_CMD} $@
}

# use it method to get a particular field from the returned JSON string
get_field() {
  prereqs
  if [ -n "${1:-}" ]; then
    ${GITVERSION_CMD} | ${JQ_CMD} -r .${1}
  else
    ${GITVERSION_CMD}
  fi
}

ARG=${1:-}; shift || true

if [[ $ARG == 'prereqs' ]]; then
  prereqs
elif [[ $ARG == 'run' ]]; then
  run_cmd $@
elif [[ $ARG == 'f' ]]; then
  get_field ${1:-}
else
  die "method '$ARG' not found"
fi
