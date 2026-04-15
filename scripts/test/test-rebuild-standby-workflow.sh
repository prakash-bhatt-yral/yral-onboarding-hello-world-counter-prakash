#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKFLOW_PATH="${REPO_ROOT}/.github/workflows/rebuild-standby.yml"

fail() {
  echo "$1" >&2
  exit 1
}

[[ -f "${WORKFLOW_PATH}" ]] || fail "missing rebuild-standby workflow"

ruby -e '
require "yaml"
workflow = YAML.load_file(ARGV[0])

fail = ->(message) do
  warn(message)
  exit 1
end

unless workflow["name"] == "Rebuild Standby"
  fail.call("workflow name mismatch")
end

on_section = workflow["on"] || workflow[true] || {}
inputs = on_section.dig("workflow_dispatch", "inputs") || {}
unless inputs.key?("server_to_rebuild")
  fail.call("missing server_to_rebuild input")
end
unless inputs.key?("confirm_rebuild_standby")
  fail.call("missing confirm_rebuild_standby input")
end

jobs = workflow["jobs"] || {}
runbook = jobs["rebuild-standby"] || {}
steps = runbook["steps"] || []

step_names = steps.map { |step| step["name"] }.compact
unless step_names.include?("Verify rebuild topology")
  fail.call("missing topology verification step")
end
unless step_names.include?("Rebuild standby node")
  fail.call("missing rebuild execution step")
end
unless step_names.include?("Wait for rebuilt standby readiness")
  fail.call("missing standby readiness wait step")
end
unless step_names.include?("Verify rebuilt standby")
  fail.call("missing rebuild verification step")
end
' "${WORKFLOW_PATH}"

echo "rebuild standby workflow test ok"
