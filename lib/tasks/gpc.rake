namespace :gpc do
  desc "Read the live catalog and upsert Guideline rows"
  task catalog: :environment do
    fetched = Gpc::LiveCatalogFetcher.call
    abort(fetched.errors.full_messages.to_sentence) unless fetched.success?

    imported = Gpc::CatalogImporter.call(fetched.payload)
    abort(imported.errors.full_messages.to_sentence) unless imported.success?

    puts imported.payload.map { |key, value| "#{key}: #{value}" }.join(", ")
  end

  desc "Enqueue a full read of every live-site guideline's sections"
  task ingest: :environment do
    guidelines = Guideline.source_live_site
    guidelines.find_each { |guideline| Gpc::IngestGuidelineJob.perform_later(guideline) }

    puts "#{guidelines.count} guías encoladas en la cola ingestion"
  end
end
