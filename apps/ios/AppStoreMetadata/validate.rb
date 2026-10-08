#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Checks every App Store Connect metadata field against Apple's limits before
# you paste any of it. Counts Unicode code points, which is what App Store
# Connect counts — a Devanagari or Han string is shorter here than its byte
# length suggests.
#
#   ./validate.rb

ROOT = __dir__
LIMITS = {
  "name" => 30,
  "subtitle" => 30,
  "promotional_text" => 170,
  "keywords" => 100,
  "description" => 4000,
  "release_notes" => 4000
}.freeze

LOCALES = %w[en-US es-MX fr-FR de-DE hi zh-Hans].freeze

errors = []
rows = []

LOCALES.each do |locale|
  dir = File.join(ROOT, locale)
  unless Dir.exist?(dir)
    errors << "#{locale}: directory missing"
    next
  end

  LIMITS.each do |field, limit|
    path = File.join(dir, "#{field}.txt")
    unless File.exist?(path)
      errors << "#{locale}/#{field}.txt is missing"
      next
    end

    value = File.read(path, encoding: "UTF-8").strip
    length = value.codepoints.length

    errors << "#{locale}/#{field}: empty" if value.empty?
    errors << "#{locale}/#{field}: #{length} characters, limit is #{limit}" if length > limit

    if field == "keywords"
      errors << "#{locale}/keywords: has a space after a comma (wastes characters)" if value.include?(", ")
      duplicates = value.split(",").map(&:strip).tally.select { |_, n| n > 1 }.keys
      errors << "#{locale}/keywords: repeats #{duplicates.join(', ')}" unless duplicates.empty?
    end

    rows << [locale, field, length, limit]
  end
end

width = LIMITS.keys.map(&:length).max
rows.group_by(&:first).each do |locale, group|
  puts locale
  group.each do |_, field, length, limit|
    bar = length > limit ? "OVER" : "#{(100.0 * length / limit).round}%"
    puts format("  %-#{width}s %5d / %-5d %s", field, length, limit, bar)
  end
end

if errors.empty?
  puts "\nAll #{rows.length} fields are within App Store Connect limits."
else
  warn "\nProblems:"
  errors.each { |e| warn "  - #{e}" }
  exit 1
end
