namespace :questions do
  desc "Generate clinical cases from current guidelines: rake questions:generate[count]"
  task :generate, [:count] => :environment do |_task, args|
    count = (args[:count] || 10).to_i
    provider = Llm::Provider.for(:generator)
    abort("Falta la clave del generador. Revisa .env") unless provider.configured?

    run = GenerationRun.create!(
      purpose: "generation", provider: provider.name,
      model: provider.model, started_at: Time.current
    )

    guidelines = Guideline.current
                          .joins(guideline_sections: :recommendations)
                          .where(guideline_sections: { kind: GuidelineSection::ACTIONABLE_KINDS })
                          .distinct.limit(count)

    # A fixed rotation rather than a random draw, so a run is reproducible. Long
    # vignettes alternate with short ones, and English lands on a schedule.
    #
    # ENGLISH_SHARE is right for the full corpus and wrong for a small batch: at 8% the
    # first English case falls on the 13th, so a 12-guideline sample gets none and nobody
    # reviewing it ever sees one. Below that threshold the last case is forced to English
    # instead — the sample is deliberately over-representative, which is what a sample is
    # for.
    english_every = (1 / Questions::CaseGenerator::ENGLISH_SHARE).round
    forced_english = count < english_every ? count - 1 : nil

    guidelines.each_with_index do |guideline, index|
      detail = index.even? ? :full_workup : :focused
      scheduled = english_every.positive? && index.positive? && (index % english_every).zero?
      locale = index == forced_english || scheduled ? "en" : "es"

      result = Questions::CaseGenerator.call(guideline, run: run, detail: detail, locale: locale)
      state = result.success? ? "#{result.payload[:cases].size} casos" : result.errors.full_messages.first
      puts "#{guideline.catalog_key} [#{detail}/#{locale}] #{state}"
    end

    run.update!(status: "completed", finished_at: Time.current)
    puts "\ncasos=#{run.cases_created} descartadas=#{run.rejections} tokens=#{run.total_tokens}"
  end

  desc "Write the generated bank to one portable file: rake questions:export[path]"
  task :export, [:path] => :environment do |_task, args|
    result = Questions::Exporter.call(args[:path] || "tmp/question-bank.jsonl.gz")
    abort(result.errors.full_messages.to_sentence) unless result.success?

    payload = result.payload
    puts "#{payload[:path]} · #{payload[:cases]} casos · #{payload[:questions]} preguntas · " \
         "#{payload[:runs]} corridas · #{ActiveSupport::NumberHelper.number_to_human_size(payload[:bytes])}"
  end

  desc "Load a file written by questions:export into this database [path]"
  task :import, [:path] => :environment do |_task, args|
    result = Questions::Importer.call(args[:path] || "tmp/question-bank.jsonl.gz")
    abort(result.errors.full_messages.to_sentence) unless result.success?

    puts result.payload.map { |key, value| "#{key}: #{value}" }.join(", ")
  end
end
