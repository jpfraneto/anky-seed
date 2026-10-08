#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

ROOT = File.expand_path("..", __dir__)
CATALOGS = Dir.glob(File.join(ROOT, "Anky", "*.lproj", "Localizable.strings")).sort
ENGLISH = File.join(ROOT, "Anky", "en.lproj", "Localizable.strings")

def catalog(path)
  output, status = Open3.capture2e("plutil", "-convert", "json", "-o", "-", path)
  abort "Invalid strings catalog #{path}:\n#{output}" unless status.success?
  JSON.parse(output)
end

def placeholders(value)
  value.scan(/%(?:\d+\$)?[@df]/).sort
end

def swift_literal(value)
  value.gsub('\\n', "\n").gsub('\\"', '"').gsub('\\\\', '\\')
end

errors = []
english = catalog(ENGLISH)

CATALOGS.each do |path|
  localized = catalog(path)
  locale = File.basename(File.dirname(path), ".lproj")
  missing = english.keys - localized.keys
  extra = localized.keys - english.keys
  errors << "#{locale}: missing keys: #{missing.join(' | ')}" unless missing.empty?
  errors << "#{locale}: extra keys: #{extra.join(' | ')}" unless extra.empty?

  (english.keys & localized.keys).each do |key|
    next if placeholders(english.fetch(key)) == placeholders(localized.fetch(key))
    errors << "#{locale}: format placeholders differ for #{key.inspect}"
  end
end

# Every literal sent through either localization entry point must exist in the
# canonical English catalog. Otherwise Bundle falls back to the raw key.
Dir.glob(File.join(ROOT, "Anky", "**", "*.swift")).sort.each do |path|
  source = File.read(path)
  [/AnkyLocalization\.ui\(\s*"([^"\\]*(?:\\.[^"\\]*)*)"/m,
   /AnkyCopyRegistry\.localized\(\s*"([^"\\]*(?:\\.[^"\\]*)*)"/m].each do |pattern|
    source.to_enum(:scan, pattern).each do
      match = Regexp.last_match
      key = swift_literal(match[1])
      next if english.key?(key)
      line = source[0...match.begin(0)].count("\n") + 1
      errors << "#{path}:#{line}: missing localization key #{key.inspect}"
    end
  end
end

# Settings and writing controls pass literals through shared row/choice
# builders. Keep those indirect localization sites covered too.
indirect_paths = Dir.glob(File.join(ROOT, "Anky", "Features", "**", "*.swift")).sort
indirect_patterns = [
  /section\(title:\s*"([^"]+)"/,
  /(?:title|subtitle|label|hint|accessibilityLabel|accessibilityHint):\s*"([^"]+)"/
]
indirect_paths.each do |path|
  source = File.read(path)
  indirect_patterns.each do |pattern|
    source.to_enum(:scan, pattern).each do
      match = Regexp.last_match
      key = swift_literal(match[1])
      next if key.include?("\\(") || key == "∞" || key.match?(/\A[a-z0-9_.-]+\z/) || english.key?(key)
      line = source[0...match.begin(0)].count("\n") + 1
      errors << "#{path}:#{line}: missing indirect localization key #{key.inspect}"
    end
  end
end

if errors.empty?
  puts "Localization verification passed: #{CATALOGS.length} locales, #{english.length} keys each."
else
  warn errors.join("\n")
  exit 1
end
