# Builds the Specialty / Branch / Topic tree from db/seeds/taxonomy.yml.
#
# Idempotent on slugs, which are derived from names rather than written, so editing the
# file and re-running is the supported way to change the taxonomy. Positions come from
# the order in the file — that order is the study plan's reading order, so it is
# deliberate rather than alphabetical.
module Taxonomy
  class Seeder < ApplicationService
    SOURCE = Rails.root.join("db/seeds/taxonomy.yml")

    def initialize(path = SOURCE)
      super()
      @path = path
    end

    def call
      return failure("No existe #{path}") unless File.exist?(path)

      counts = Hash.new(0)
      ActiveRecord::Base.transaction do
        YAML.load_file(path).each_with_index { |attributes, index| seed_specialty(attributes, index + 1, counts) }
      end

      success(counts)
    rescue ActiveRecord::RecordInvalid => e
      failure("No se pudo guardar la taxonomía: #{e.record.errors.full_messages.to_sentence}")
    end

    private

    attr_reader :path

    def seed_specialty(attributes, position, counts)
      specialty = upsert(Specialty, attributes["name"], counts, :specialties) do |record|
        record.kind = attributes["kind"]
        record.color_token = attributes["color_token"]
        record.position = position
      end

      attributes["branches"].each_with_index { |branch, index| seed_branch(specialty, branch, index + 1, counts) }
    end

    def seed_branch(specialty, attributes, position, counts)
      branch = upsert(Branch, attributes["name"], counts, :branches) do |record|
        record.specialty = specialty
        record.position = position
      end

      attributes["topics"].each_with_index { |topic, index| seed_topic(branch, topic, index + 1, counts) }
    end

    def seed_topic(branch, attributes, position, counts)
      upsert(Topic, attributes["name"], counts, :topics) do |record|
        record.branch = branch
        record.position = position
        record.aliases = attributes["aliases"] || []
      end
    end

    def upsert(model, name, counts, key)
      record = model.find_or_initialize_by(slug: name.parameterize)
      counts[record.new_record? ? key : :"#{key}_updated"] += 1
      record.name = name
      yield(record)
      record.save!
      record
    end
  end
end
