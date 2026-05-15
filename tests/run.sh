#!/usr/bin/env bash
set -eu

TEST_FILE="$(dirname "$0")/skill_set_tests.sh"
if [ -f "$TEST_FILE" ]; then
  bash "$TEST_FILE"
fi
