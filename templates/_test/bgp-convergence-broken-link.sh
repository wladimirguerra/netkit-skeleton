#!/usr/bin/env bash
#
# This script test and record logs of update from bgpd
# simulating a broken link
#

scriptName="${0##*/}"

declare -i DEFAULT_TIMEOUT=30
declare -i DEFAULT_INTERVAL=30