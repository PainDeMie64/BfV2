#!/bin/bash
cd "$(dirname "$0")"
cat *.as > ~/BfV2.as
echo "Built ~/BfV2.as ($(wc -l < ~/BfV2.as) lines)"
