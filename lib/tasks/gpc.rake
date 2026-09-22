namespace :gpc do
  desc "Read the live catalog and upsert Guideline rows"
  task catalog: :environment do
    fetched = Gpc::LiveCatalogFetcher.call
    abort(fetched.errors.full_messages.to_sentence) unless fetched.success?

    imported = Gpc::CatalogImporter.call(fetched.payload)
    abort(imported.errors.full_messages.to_sentence) unless imported.success?

    puts imported.payload.map { |key, value| "#{key}: #{value}" }.join(", ")
  end

  desc "Enqueue every guideline summary the Wayback Machine holds for CENETEC"
  task archive: :environment do
    fetched = Gpc::ArchiveCatalogFetcher.call
    abort(fetched.errors.full_messages.to_sentence) unless fetched.success?

    entries = fetched.payload
    entries.each { |entry| Gpc::IngestArchivedGuidelineJob.perform_later(entry) }

    puts "#{entries.size} guías archivadas encoladas en la cola ingestion"
  end

  desc "Re-derive archived guideline titles from stored text, without refetching"
  task retitle: :environment do
    result = Gpc::Retitler.call
    abort(result.errors.full_messages.to_sentence) unless result.success?

    puts result.payload.map { |key, value| "#{key}: #{value}" }.join(", ")
  end

  desc "Link every guideline to the topics its title names"
  task link: :environment do
    result = Gpc::TopicLinker.call
    abort(result.errors.full_messages.to_sentence) unless result.success?

    puts result.payload.map { |key, value| "#{key}: #{value}" }.join(", ")
  end

  desc "Write guidelines and their sections to a portable file [path]"
  task :export, [:path] => :environment do |_task, args|
    result = Gpc::CorpusExporter.call(args[:path] || "tmp/gpc-corpus.jsonl.gz")
    abort(result.errors.full_messages.to_sentence) unless result.success?

    payload = result.payload
    puts "#{payload[:path]} · #{payload[:guidelines]} guías · #{payload[:sections]} secciones · " \
         "#{ActiveSupport::NumberHelper.number_to_human_size(payload[:bytes])}"
  end

  desc "Load a file written by gpc:export into this database [path]"
  task :import, [:path] => :environment do |_task, args|
    result = Gpc::CorpusImporter.call(args[:path] || "tmp/gpc-corpus.jsonl.gz")
    abort(result.errors.full_messages.to_sentence) unless result.success?

    puts result.payload.map { |key, value| "#{key}: #{value}" }.join(", ")
    puts "Ahora corre gpc:reparse, gpc:taxonomy y gpc:link para reconstruir lo derivado."
  end

  desc "Re-read stored section bodies through the current parser, without touching the site"
  task reparse: :environment do
    sections = GuidelineSection.graded.original
    before = Recommendation.count

    # A section whose statements come out the same is left alone: its recommendations
    # may already be cited by questions, and deleting them would take the questions'
    # provenance with them.
    sections.includes(:recommendations).find_each do |section|
      parsed = Gpc::RecommendationParser.call(section.body).payload
      stored = section.recommendations.map { |r| r.slice(*parsed.first.to_h.keys).symbolize_keys }
      next if parsed == stored

      ActiveRecord::Base.transaction do
        section.recommendations.destroy_all
        parsed.each { |attributes| section.recommendations.create!(attributes) }
      end
    rescue ActiveRecord::InvalidForeignKey
      puts "#{section.guideline.catalog_key} #{section.external_id}: " \
           "hay preguntas que citan lo que el parser ya no produce"
    end

    Recommendation.joins(:guideline_section).merge(GuidelineSection.original.where.not(kind: GuidelineSection::GRADED_KINDS)).destroy_all

    archived = Hash.new(0)
    GuidelineSection.kind_archived_document.includes(:guideline).find_each do |document|
      result = Gpc::ArchiveSectionBuilder.call(document)
      next puts(result.errors.full_messages.to_sentence) if result.failure?

      archived[:guidelines] += 1 if result.payload[:recommendations].positive?
      archived[:recommendations] += result.payload[:recommendations]
    end

    puts "#{sections.count} secciones · #{before} → #{Recommendation.count} recomendaciones"
    puts "archivo: #{archived[:recommendations]} recomendaciones de #{archived[:guidelines]} guías"
  end

  desc "Enqueue a full read of every live-site guideline's sections"
  task ingest: :environment do
    guidelines = Guideline.source_live_site
    guidelines.find_each { |guideline| Gpc::IngestGuidelineJob.perform_later(guideline) }

    puts "#{guidelines.count} guías encoladas en la cola ingestion"
  end

  desc "Re-read each live guideline's menu and store where its sections sit, without refetching bodies"
  task renav: :environment do
    result = Gpc::NavigationRefresher.call
    abort(result.errors.full_messages.to_sentence) unless result.success?

    puts result.payload.map { |key, value| "#{key}: #{value}" }.join(", ")
  end

  desc "Build the figure library from stored section text, downloading what is missing"
  task images: :environment do
    result = Gpc::ImageIngester.call
    puts result.payload.map { |key, value| "#{key}: #{value}" }.join(", ")
    # A partial run still reports its counts: one unreachable file is not a reason to
    # say nothing about the 900 that arrived. Response#errors is nil on success.
    puts result.errors.full_messages.first(10) if result.failure?
  end
end
