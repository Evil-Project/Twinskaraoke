#!/usr/bin/env bash
# Prints the UDID of an available simulator on the newest runtime of one OS
# major version, so CI tests on a known OS instead of whatever happens to be
# newest on the runner image.
#
#   Scripts/ci-simulator.sh iOS 27 iPhone
#   Scripts/ci-simulator.sh watchOS 27 "Apple Watch"
#
# Name-only destinations imply OS:latest and fail when a device exists only
# under another runtime, so CI targets the UDID instead.
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 <iOS|watchOS|tvOS> <major version> <device name prefix>" >&2
  exit 2
fi

xcrun simctl list devices available -j | ruby -rjson -e '
  platform, major, prefix = ARGV
  devices = JSON.parse(STDIN.read)["devices"]
  pattern = /SimRuntime\.#{Regexp.escape(platform)}-#{Integer(major)}-/
  runtimes = devices.keys.select { |runtime| runtime =~ pattern }
  runtimes.sort_by { |runtime| runtime.scan(/\d+/).map(&:to_i) }.reverse_each do |runtime|
    match = devices[runtime].find { |d| d["isAvailable"] && d["name"].start_with?(prefix) }
    next unless match
    warn "Using #{match["name"]} on #{runtime.split(".").last} (#{match["udid"]})"
    puts match["udid"]
    exit 0
  end
  warn "No available \"#{prefix}\" simulator on #{platform} #{major}. Installed runtimes:"
  devices.keys.sort.each { |runtime| warn "  #{runtime}" }
  exit 1
' "$@"
