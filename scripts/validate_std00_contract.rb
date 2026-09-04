#!/usr/bin/env ruby

require "json"
require "yaml"

ROOT = File.expand_path("..", __dir__)
COMMON_VOCAB_PATH = File.join(ROOT, "規格/v0.1/common-vocabulary.yaml")
POSITIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/std-00-positive-fixtures.json")
NEGATIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/std-00-negative-fixtures.json")

EXPECTED_PHASE_1_PROFILES = %w[
  PDF_REGION_V1
  MARKDOWN_TEXT_V1
  JIRA_CLOUD_ENTITY_SEGMENT_V1
].freeze

EXPECTED_NEGATIVE_FIXTURES = %w[
  same-cloudevent-redelivery
  redelivery-payload-mismatch
  same-source-new-revision
  same-payload-different-sources
  single-jira-404
  permission-revoked
  project-deletion-missed-webhooks
  non-i-json-jcs-input
  source-event-without-native-event-id
  pdf-anchor-parser-risk
  jira-key-renamed
  cross-client-object-link
  workrecord-global-summary-leak
  model-link-confidence
  openlineage-complete
  projection-deletion
  source-anchor-missing-representation-digest
].freeze

SHA256_PATTERN = /\Asha256:[0-9a-f]{64}\z/.freeze

def assert(condition, message, failures)
  failures << message unless condition
end

def read_json(path)
  JSON.parse(File.read(path))
end

def read_yaml(path)
  YAML.safe_load(File.read(path), permitted_classes: [], aliases: false)
end

def dig_path(payload, path)
  path.split(".").reduce(payload) do |cursor, key|
    return nil unless cursor.is_a?(Hash)

    cursor[key]
  end
end

def validate_source_anchor_digest_contract(common_vocab, positive_fixtures, negative_fixtures, failures)
  assert(common_vocab.dig("schema", "status") == "LOCKED", "common-vocabulary.yaml schema.status 必須為 LOCKED", failures)
  assert(positive_fixtures["status"] == "LOCKED", "std-00-positive-fixtures.json status 必須為 LOCKED", failures)
  assert(negative_fixtures["status"] == "LOCKED", "std-00-negative-fixtures.json status 必須為 LOCKED", failures)

  phase_1_profiles = common_vocab.dig("source_anchor_profiles", "phase_1").to_a
  assert(phase_1_profiles == EXPECTED_PHASE_1_PROFILES, "source_anchor_profiles.phase_1 必須精確列出 STD-00 三個 profile", failures)

  digest_basis = common_vocab.dig("source_anchor_profiles", "digest_basis")
  assert(digest_basis.is_a?(Hash), "source_anchor_profiles.digest_basis 必須存在", failures)

  fixtures_by_profile = positive_fixtures.fetch("fixtures").to_h do |fixture|
    [fixture.dig("anchor", "profile"), fixture]
  end

  EXPECTED_PHASE_1_PROFILES.each do |profile|
    fixture = fixtures_by_profile[profile]
    assert(!fixture.nil?, "positive fixture 必須覆蓋 #{profile}", failures)
    next if fixture.nil?

    basis = digest_basis.is_a?(Hash) ? digest_basis[profile] : nil
    assert(basis.is_a?(Hash), "#{profile} 必須有 digest basis", failures)
    digest_field = basis.is_a?(Hash) ? basis["fixture_digest_field"] : nil
    assert(digest_field.is_a?(String) && !digest_field.empty?, "#{profile} digest basis 必須宣告 fixture_digest_field", failures)

    representation_digest = fixture.dig("anchor", "representation_digest")
    assert(representation_digest.is_a?(String), "#{fixture.fetch("name")} anchor.representation_digest 必須存在", failures)
    assert(representation_digest.nil? || representation_digest.match?(SHA256_PATTERN), "#{fixture.fetch("name")} anchor.representation_digest 必須是 sha256 digest", failures)

    next unless digest_field.is_a?(String) && representation_digest.is_a?(String)

    expected_digest = dig_path(fixture, digest_field)
    assert(expected_digest == representation_digest, "#{fixture.fetch("name")} anchor.representation_digest 必須等於 #{digest_field}", failures)
  end

  negative_names = negative_fixtures.fetch("cases").map { |entry| entry.fetch("name") }
  assert(negative_names == EXPECTED_NEGATIVE_FIXTURES, "negative fixtures 必須精確覆蓋 STD-00 17 條負向案例", failures)
  assert(
    negative_names.include?("source-anchor-missing-representation-digest"),
    "negative fixtures 必須覆蓋 SourceAnchor 缺 representation_digest",
    failures
  )
end

def main
  failures = []
  common_vocab = read_yaml(COMMON_VOCAB_PATH)
  positive_fixtures = read_json(POSITIVE_FIXTURE_PATH)
  negative_fixtures = read_json(NEGATIVE_FIXTURE_PATH)

  validate_source_anchor_digest_contract(common_vocab, positive_fixtures, negative_fixtures, failures)

  if failures.empty?
    puts "STD-00 validator PASS"
    exit 0
  end

  warn "STD-00 validator FAIL"
  failures.each { |failure| warn "- #{failure}" }
  exit 1
end

main if $PROGRAM_NAME == __FILE__
