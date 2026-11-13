#!/bin/bash
# SPDX-License-Identifier: MIT
#
# ci/plan.sh
#
# Decides which templates the build jobs get. Reads the GitHub context from
# the environment (EVENT, INPUT, BEFORE, PR_BASE, PR_HEAD, REF, GITHUB_SHA)
# and prints the template names on one line.
#
#   workflow_dispatch   INPUT = "all" or names
#   pull_request        templates changed between PR base and head
#   push to main        templates changed by the push (BEFORE..GITHUB_SHA)
#   push to a branch    templates changed since the branch left main
#
# Everything is rebuilt when the base is unknown (new branch, first push)
# or when ci/void-packages.ref changed. If only CI files changed, one small
# template is built as a canary.
set -euo pipefail
cd "$(dirname "$0")/.."

zero=0000000000000000000000000000000000000000
canary=xlibre-xorgproto
base="" head="${GITHUB_SHA:-HEAD}"

case "${EVENT:?}" in
	workflow_dispatch)
		if [ "${INPUT:-all}" = all ]; then mode="all"; else mode="list"; fi ;;
	pull_request)
		base="${PR_BASE:?}" head="${PR_HEAD:?}" mode="diff" ;;
	push)
		if [ "${REF:?}" = refs/heads/main ]; then
			base="${BEFORE:-}"
		else
			base="$(git merge-base origin/main "$head" 2>/dev/null || true)"
		fi
		mode="diff" ;;
	*)
		echo "unknown event $EVENT" >&2; exit 2 ;;
esac

if [ "$mode" = diff ]; then
	if [ -z "$base" ] || [ "$base" = "$zero" ] || ! git cat-file -e "$base^{commit}" 2>/dev/null; then
		echo "base unknown: rebuild everything" >&2
		mode="all"
	elif git diff --name-only "$base" "$head" | grep -qx 'ci/void-packages.ref'; then
		echo "void-packages pin changed: rebuild everything" >&2
		mode="all"
	fi
fi

case "$mode" in
	all)
		list="$(bash ci/changed.sh all)" ;;
	list)
		# shellcheck disable=SC2086  # names separated by spaces
		list="$(bash ci/changed.sh list ${INPUT})" ;;
	diff)
		list="$(bash ci/changed.sh diff "$base" "$head")"
		if [ -z "$list" ] && git diff --name-only "$base" "$head" |
			grep -qE '^(ci/|\.github/workflows/build\.yml$)'; then
			echo "only CI changed: canary build of $canary" >&2
			list="$canary"
		fi ;;
esac

echo "$list" | xargs
