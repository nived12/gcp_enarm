namespace :gpc do
  desc "Read the live catalog and upsert Guideline rows"
  task catalog: :environment do
    fetched = Gpc::LiveCatalogFetcher.call
    abort(fetched.errors.full_messages.to_sentence) unless fetched.success?

    imported = Gpc::CatalogImporter.call(fetched.payload)
    abort(imported.errors.full_messages.to_sentence) unless imported.success?

    puts imported.payload.map { |key, value| "#{key}: #{value}" }.join(", ")
  end

  desc "Re-read stored section bodies through the current parser, without touching the site"
  task reparse: :environment do
    sections = GuidelineSection.graded
    before = Recommendation.count

    sections.find_each do |section|
      section.recommendations.destroy_all
      Gpc::RecommendationParser.call(section.body).payload.each do |attributes|
        section.recommendations.create!(attributes)
      end
    end

    Recommendation.joins(:guideline_section).merge(GuidelineSection.where.not(kind: GuidelineSection::GRADED_KINDS)).destroy_all

    puts "#{sections.count} secciones · #{before} → #{Recommendation.count} recomendaciones"
  end

  desc "Enqueue a full read of every live-site guideline's sections"
  task ingest: :environment do
    guidelines = Guideline.source_live_site
    guidelines.find_each { |guideline| Gpc::IngestGuidelineJob.perform_later(guideline) }

    puts "#{guidelines.count} guías encoladas en la cola ingestion"
  end
end
