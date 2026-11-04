#!/usr/bin/env bash
# Prints the UDID of an available simulator on the newest runtime of one OS
# major version, so CI tests on a known OS instead of whatever happens to be
# newest on the runner image.
#
#   Scripts/ci-simulator.sh iOS 27 iPhone 'Duo|Fold'
#   Scripts/ci-simulator.sh watchOS 27 "Apple Watch"
#
# The optional 4th argument is a regex of device names to skip. CI skips
# foldable iPhones: their unfolded, iPad-like layout breaks the compact-width
# UI tests.
#
# Name-only destinations imply OS:latest and fail when a device exists only
# under another runtime, so CI targets the UDID instead.
set -euo pipefail

if [[ $# -lt 3 || $# -gt 4 ]]; then
  echo "usage: $0 <iOS|watchOS|tvOS> <major version> <device name prefix> [exclude regex]" >&2
  exit 2
fi

xcrun simctl list devices available -j | ruby -rjson -e '
  platform, major, prefix, exclude = ARGV
  skip = exclude.to_s.empty? ? nil : Regexp.new(exclude)
  devices = JSON.parse(STDIN.read)["devices"]
  pattern = /SimRuntime\.#{Regexp.escape(platform)}-#{Integer(major)}-/
  runtimes = devices.keys.select { |runtime| runtime =~ pattern }
  runtimes.sort_by { |runtime| runtime.scan(/\d+/).map(&:to_i) }.reverse_each do |runtime|
    candidates = devices[runtime].select { |d| d["isAvailable"] && d["name"].start_with?(prefix) }
    next if candidates.empty?
    warn "#{runtime.split(".").last} has: #{candidates.map { |d| d["name"] }.join(", ")}"
    match = candidates.find { |d| skip.nil? || d["name"] !~ skip }
    next unless match
    warn "Using #{match["name"]} on #{runtime.split(".").last} (#{match["udid"]})"
    puts match["udid"]
    exit 0
  end
  warn "No available \"#{prefix}\" simulator on #{platform} #{major}#{skip ? " (skipping /#{exclude}/)" : ""}. Installed runtimes:"
  devices.keys.sort.each { |runtime| warn "  #{runtime}" }
  exit 1
' "$@"
