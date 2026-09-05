#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
ruby -ryaml -e '
  w = YAML.load_file(".github/workflows/testflight.yml")
  triggers = w["on"] || w[true]
  abort "Wrong CI dependency" unless triggers["workflow_run"]["workflows"] == ["iOS"]
  abort "Wrong branch" unless triggers["workflow_run"]["branches"] == ["main"]
  abort "Missing recovery schedule" unless triggers["schedule"]
  abort "Uploads must not cancel" unless w["concurrency"]["cancel-in-progress"] == false
  job = w["jobs"]["plan"]
  abort "Missing success gate" unless job["if"].include?("conclusion == '\''success'\''")
  abort "Missing trusted push gate" unless job["if"].include?("event == '\''push'\''")
  w["jobs"].values.flat_map { |j| j["steps"] }.each do |step|
    next unless step["run"]
    abort "Shell expression interpolation" if step["run"].include?("${{")
    IO.popen(["bash", "-n"], "w") { |io| io.write(step["run"]) }
    abort "Invalid shell" unless $?.success?
  end
'
python3 -B -m unittest discover -s scripts -p 'test_*testflight*.py'
echo 'TestFlight workflow contract passed'
