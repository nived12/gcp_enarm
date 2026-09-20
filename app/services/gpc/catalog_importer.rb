# Upserts fetched catalog entries into Guideline rows.
#
# Idempotent on catalog_key: a re-run touches ingested_at on everything it saw and
# writes attributes only where content_hash changed. That distinction matters —
# "we checked today" and "they republished" are different facts, and the second one
# is what should later invalidate generated questions.
module Gpc
  class CatalogImporter < ApplicationService
    # Everything that describes the guideline itself. ingested_at is excluded on
    # purpose: a new timestamp must not read as a change.
    HASHED_ATTRIBUTES = %w[
      catalog_key title institution year source external_id
      catalog_url document_url specialty_labels levels_of_care
    ].freeze

    def initialize(entries)
      super()
      @entries = entries
    end

    def call
      created = 0
      updated = 0
      unchanged = 0

      @entries.each do |entry|
        attributes = entry.stringify_keys.merge("content_hash" => content_hash_for(entry))
        guideline = Guideline.find_by(catalog_key: attributes["catalog_key"])

        if guideline.nil?
          Guideline.create!(attributes.merge("ingested_at" => Time.current))
          created += 1
        elsif guideline.content_hash == attributes["content_hash"]
          guideline.update_column(:ingested_at, Time.current)
          unchanged += 1
        else
          guideline.update!(attributes.merge("ingested_at" => Time.current))
          updated += 1
        end
      end

      success(created: created, updated: updated, unchanged: unchanged)
    rescue ActiveRecord::RecordInvalid => e
      failure("No se pudo guardar la guía: #{e.record.errors.full_messages.to_sentence}")
    end

    private

    def content_hash_for(entry)
      canonical = HASHED_ATTRIBUTES.index_with { |key| entry.stringify_keys[key] }
      Digest::SHA256.hexdigest(canonical.to_json)
    end
  end
end
