#!/bin/bash
set -e
cd "$(dirname "$0")"
python3 scripts/check_scripting_reference.py
cat *.as > ~/BfV2.as
echo "Built ~/BfV2.as ($(wc -l < ~/BfV2.as) lines)"
