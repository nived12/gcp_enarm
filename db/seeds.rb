# Runs on every deploy, from bin/boot. Everything here must be idempotent.
#
# The taxonomy seeds itself rather than being a deploy step someone has to remember:
# it is derived from a file in the repo, costs a second, and is the one piece of
# reference data the app cannot start empty. The GPC corpus is not here — it is
# scraped or imported, and is far too large to belong in seeds. See DEPLOY.md.
result = Taxonomy::Seeder.call
abort("No se pudo sembrar la taxonomía: #{result.errors.full_messages.to_sentence}") unless result.success?

Rails.logger.info("Taxonomía: #{result.payload.inspect}")
