#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Merges the per-locale screenshot fixtures into the single JSON the app
# bundles, and regenerates the locale manifest the compositor reads.
#
# Edit AppStoreScreenshots/fixtures/<locale>.json — never the generated
# Anky/Support/Screenshot/ScreenshotFixtures.json.

require "json"

ROOT = File.expand_path("..", __dir__)
FIXTURES = File.join(ROOT, "AppStoreScreenshots", "fixtures")
BUNDLED = File.join(ROOT, "Anky", "Support", "Screenshot", "ScreenshotFixtures.json")
MANIFEST = File.join(ROOT, "AppStoreScreenshots", "locales.json")

SCENES = %w[ritual simplicity reflection archive recording].freeze
ORDER = %w[en es fr de hi zh-Hans].freeze
REQUIRED = %w[appLocale appStoreLocale languageName simulatorLanguage simulatorLocale
              keyboards headlines ritual simplicity feature archive].freeze

errors = []
locales = {}
manifest = []

ORDER.each do |code|
  path = File.join(FIXTURES, "#{code}.json")
  unless File.exist?(path)
    errors << "#{code}: fixtures/#{code}.json is missing"
    next
  end

  begin
    fixture = JSON.parse(File.read(path))
  rescue JSON::ParserError => e
    errors << "#{code}: invalid JSON — #{e.message}"
    next
  end

  missing = REQUIRED - fixture.keys
  errors << "#{code}: missing keys #{missing.join(', ')}" unless missing.empty?
  errors << "#{code}: appLocale is #{fixture['appLocale'].inspect}, expected #{code.inspect}" if fixture["appLocale"] != code

  SCENES.each do |scene|
    headline = fixture.dig("headlines", scene)
    errors << "#{code}: no headline for scene '#{scene}'" if headline.nil? || headline.strip.empty?
  end

  %w[ritual simplicity].each do |scene|
    writing = fixture[scene]
    next errors << "#{code}: '#{scene}' block missing" if writing.nil?
    errors << "#{code}: #{scene}.text is empty" if writing["text"].to_s.strip.empty?
    errors << "#{code}: #{scene}.elapsedMs must be positive" unless writing["elapsedMs"].to_i.positive?
    errors << "#{code}: #{scene}.text contains a newline (the writer rejects them)" if writing["text"].to_s.include?("\n")
  end

  feature = fixture["feature"] || {}
  errors << "#{code}: feature.reflection is empty" if feature["reflection"].to_s.strip.empty?
  errors << "#{code}: feature.text is empty" if feature["text"].to_s.strip.empty?

  archive = fixture["archive"] || []
  errors << "#{code}: archive has #{archive.length} entries, need at least 11 (+ the feature writing = 12)" if archive.length < 11
  archive.each_with_index do |entry, index|
    errors << "#{code}: archive[#{index}] has no date" if entry["date"].to_s.empty?
    errors << "#{code}: archive[#{index}] text is empty" if entry["text"].to_s.strip.empty?
    errors << "#{code}: archive[#{index}] text contains a newline" if entry["text"].to_s.include?("\n")
  end

  locales[code] = fixture
  manifest << fixture.slice("appLocale", "appStoreLocale", "languageName",
                            "simulatorLanguage", "simulatorLocale", "keyboards")
end

unless errors.empty?
  warn "Screenshot fixtures are not valid:"
  errors.each { |e| warn "  - #{e}" }
  exit 1
end

File.write(BUNDLED, JSON.pretty_generate({ "version" => 1, "scenes" => SCENES, "locales" => locales }) + "\n")
File.write(MANIFEST, JSON.pretty_generate({ "locales" => manifest }) + "\n")
puts "fixtures ok — #{locales.length} locales, #{SCENES.length} scenes each"
