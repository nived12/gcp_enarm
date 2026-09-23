namespace :questions do
  desc "Generate clinical cases: rake questions:generate[calls,budget_usd,source] (source: live_site|web_archive)"
  task :generate, %i[calls budget source] => :environment do |_task, args|
    calls = (args[:calls] || 10).to_i
    budget = args[:budget].presence&.to_f
    provider = Llm::Provider.for(:generator)
    abort("Falta la clave del generador. Revisa .env") unless provider.configured?

    guidelines = Guideline.generatable
    guidelines = guidelines.where(source: args[:source]) if args[:source].present?

    run = GenerationRun.create!(
      purpose: "generation", provider: provider.name,
      model: provider.model, started_at: Time.current
    )

    result = Questions::GenerationRunner.call(
      run: run, calls: calls, budget_usd: budget, guidelines: guidelines, on_progress: ->(line) { puts line }
    )
    run.update!(status: result.success? ? "completed" : "failed", finished_at: Time.current)
    abort(result.errors.full_messages.to_sentence) if result.failure?

    run.reload
    puts "\ncasos=#{run.cases_created} descartadas=#{run.rejections} tokens=#{run.total_tokens} " \
         "costo=$#{format("%.4f", run.cost_usd)}#{" (tope alcanzado)" if result.payload[:stopped_at_budget]}"
    puts "Detenida tras #{Questions::GenerationRunner::FAILURES_IN_A_ROW} fallas seguidas." \
         if result.payload[:stopped_after_failures]
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

  desc "File every case under its guideline's current main topic, after taxonomy:seed and gpc:link"
  task refile: :environment do
    puts "casos reubicados: #{Questions::Refiler.call.payload[:moved]}"
  end

  desc "Have a second model family judge unverified cases: rake questions:verify[count]"
  task :verify, [:count] => :environment do |_task, args|
    count = (args[:count] || 10).to_i
    provider = Llm::Provider.for(:verifier)
    abort("Falta la clave del verificador. Revisa .env") unless provider.configured?

    run = GenerationRun.create!(
      purpose: "verification", provider: provider.name,
      model: provider.model, started_at: Time.current
    )

    tally = Hash.new(0)
    ClinicalCase.where(verification_verdict: nil).order(:id).limit(count).each do |kase|
      result = Questions::Verifier.call(kase, run: run)
      state = result.success? ? result.payload[:verdict] : result.errors.full_messages.first
      tally[state] += 1
      rationales = result.payload[:rationales] if result.success?
      puts "caso #{kase.id}: #{state}#{" razones #{rationales.to_json}" if rationales}"
    end

    run.update!(status: "completed", finished_at: Time.current)
    puts "\n#{tally.map { |verdict, n| "#{verdict}=#{n}" }.join(" ")} tokens=#{run.total_tokens}"
  end

  desc "Publish every verifier-supported case nobody has withdrawn, and pull back any that no longer qualify"
  task publish: :environment do
    payload = Questions::Publisher.call.payload
    puts "publicados=#{payload[:published]} retirados_del_banco=#{payload[:withdrawn]} en_el_banco=#{payload[:live]}"
  end

  desc "Write why each distractor is wrong, for cases that lack it: rake questions:write_rationales[count]"
  task :write_rationales, [:count] => :environment do |_task, args|
    count = (args[:count] || 10).to_i
    provider = Llm::Provider.for(:generator)
    abort("Falta la clave del generador. Revisa .env") unless provider.configured?

    run = GenerationRun.create!(
      purpose: "rationales", provider: provider.name, model: provider.model, started_at: Time.current
    )

    missing = AnswerOption.where(correct: false, rationale: nil).joins(:question).select("questions.clinical_case_id")
    cases = ClinicalCase.where(id: missing).where.not(status: "retired").order(:id).limit(count)
    tally = Hash.new(0)
    cases.each do |kase|
      result = Questions::RationaleWriter.call(kase, run: run)
      state = result.success? ? "#{result.payload[:written]} razones" : result.errors.full_messages.first
      tally[result.success? ? :ok : :failed] += 1
      puts "caso #{kase.id}: #{state}"
    end

    run.update!(status: "completed", finished_at: Time.current)
    puts "\ncasos=#{tally[:ok]} fallidos=#{tally[:failed]} tokens=#{run.total_tokens} costo=$#{format(
      "%.4f",
      run.cost_usd
    )}"
  end

  desc "Judge the unjudged distractor rationales of verifier-supported cases: " \
       "rake questions:verify_rationales[count]"
  task :verify_rationales, [:count] => :environment do |_task, args|
    count = (args[:count] || 10).to_i
    provider = Llm::Provider.for(:verifier)
    abort("Falta la clave del verificador. Revisa .env") unless provider.configured?

    run = GenerationRun.create!(
      purpose: "verification", provider: provider.name, model: provider.model, started_at: Time.current,
      notes: "rationales"
    )

    unjudged = AnswerOption.rationale_unjudged.joins(:question).select("questions.clinical_case_id")
    cases = ClinicalCase.where(id: unjudged).verdict_supported.where.not(status: "retired")
    tally = Hash.new(0)
    cases.order(:id).limit(count).each do |kase|
      result = Questions::RationaleVerifier.call(kase, run: run)
      if result.success?
        result.payload.each { |verdict, n| tally[verdict] += n }
        puts "caso #{kase.id}: #{result.payload.map { |verdict, n| "#{verdict}=#{n}" }.join(" ")}"
      else
        tally[:failed_cases] += 1
        puts "caso #{kase.id}: #{result.errors.full_messages.first}"
      end
    end

    run.update!(status: "completed", finished_at: Time.current)
    puts "\n#{tally.map { |verdict, n| "#{verdict}=#{n}" }.join(" ")} tokens=#{run.total_tokens} " \
         "costo=$#{format("%.4f", run.cost_usd)}"
  end

  desc "Rewrite the rationales the verifier rejected, then run verify_rationales: " \
       "rake questions:rewrite_rationales[count]"
  task :rewrite_rationales, [:count] => :environment do |_task, args|
    count = (args[:count] || 10).to_i
    provider = Llm::Provider.for(:generator)
    abort("Falta la clave del generador. Revisa .env") unless provider.configured?

    run = GenerationRun.create!(
      purpose: "rationales", provider: provider.name, model: provider.model, started_at: Time.current,
      notes: "rewrite"
    )

    rejected = AnswerOption.rationale_rejected.joins(:question).select("questions.clinical_case_id")
    tally = Hash.new(0)
    ClinicalCase.where(id: rejected).where.not(status: "retired").order(:id).limit(count).each do |kase|
      result = Questions::RationaleWriter.call(kase, run: run, rewrite: true)
      state = result.success? ? "#{result.payload[:written]} razones" : result.errors.full_messages.first
      tally[result.success? ? :ok : :failed] += 1
      puts "caso #{kase.id}: #{state}"
    end

    run.update!(status: "completed", finished_at: Time.current)
    puts "\ncasos=#{tally[:ok]} fallidos=#{tally[:failed]} tokens=#{run.total_tokens} " \
         "costo=$#{format("%.4f", run.cost_usd)}"
    puts "Las razones reescritas quedan sin revisar: corre questions:verify_rationales."
  end
end
