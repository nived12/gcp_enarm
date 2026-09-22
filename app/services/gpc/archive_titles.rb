# Titles read by hand off the covers of archived guidelines the heuristic misnames.
# See db/seeds/archive_titles.yml.
module Gpc
  module ArchiveTitles
    SOURCE = Rails.root.join("db/seeds/archive_titles.yml")

    def self.for(catalog_key)
      all[catalog_key]
    end

    def self.all
      @all ||= YAML.load_file(SOURCE).freeze
    end
  end
end
