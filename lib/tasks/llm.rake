namespace :llm do
  desc "Show which model each role will use and whether its key is set"
  task status: :environment do
    Llm::Provider.all.each do |provider|
      state = provider.configured? ? "clave presente" : "SIN CLAVE"
      puts format("%-10s %-40s %-46s %s", provider.role, provider.to_s, provider.base_url, state)
    end

    missing = Llm::Provider.all.reject(&:configured?).map(&:role)
    puts "\nFaltan claves para: #{missing.join(", ")}. Revisa .env" if missing.any?
  end
end
