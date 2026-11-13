#!/bin/bash
# SPDX-License-Identifier: MIT
#
# ci/annotate.sh <title> <logfile>
#
# Puts the end of a log into an error annotation. Annotations are readable
# through the public API without logging in, job logs are not - this lets
# a failed run be diagnosed from outside.
set -uo pipefail
title="${1:?title}" log="${2:?log}"
[ -f "$log" ] || { echo "::error title=$title::no log ($log)"; exit 0; }
tail -n 60 "$log" | tail -c 3500 |
	sed -e 's/\x1b\[[0-9;]*m//g' |
	python3 -c 'import sys; t=sys.stdin.read().replace("%","%25").replace("\r","").replace("\n","%0A"); print("::error title='"$title"'::"+t)'
