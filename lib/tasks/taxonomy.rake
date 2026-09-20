namespace :taxonomy do
  desc "Build the specialty / branch / topic tree from db/seeds/taxonomy.yml"
  task seed: :environment do
    result = Taxonomy::Seeder.call
    abort(result.errors.full_messages.to_sentence) unless result.success?

    puts result.payload.map { |key, value| "#{key}: #{value}" }.join(", ")
  end
end
