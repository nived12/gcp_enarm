# GPCEnarm

An ENARM simulator built on Mexico's public Guías de Práctica Clínica. Clinical cases are
generated from graded GPC recommendations, and every answer cites the recommendation it
came from. Free for a granted-premium list, paid for everyone else.

The full build plan lives outside the repo at `../initial_plan.md`
(`/Users/nived/enarm_simulador/initial_plan.md`), mirrored to
`~/.claude/plans/i-want-to-create-crispy-stardust.md`.

## Non-negotiables

**Code is English. The UI is Spanish.** Every identifier — class, table, column, enum
value, route, partial, i18n key, comment — is English. Spanish exists only as *values* in
`config/locales/es.yml`. Domain terms get translated, not transliterated: `pass_number`
not `vuelta`, `catalog_key` not `clave`, `case_workshop` not `taller_casos`, `attending`
not `adscrito`, `core` not `troncal`. Someone reading this code in six months should not
need Spanish; the student using it should not see a word of English.

**Names must mean something to a reader who has not seen the source system.** `DDIMBE` is
a path segment on the government site and is not spelled out anywhere, even on that site.
So the fetchers are `Gpc::LiveCatalogFetcher` and `Gpc::ArchiveCatalogFetcher`, and the
`Guideline#source` enum is `live_site` / `web_archive`. If a name needs a glossary, it is
the wrong name.

**Never guess.** If the behaviour of a gem, an API or a config is not certain, read the
source in the bundle or fetch the docs. A plausible-looking wrong answer costs more than
the two minutes it takes to check. This applies hardest to the GPC endpoints, which are
undocumented.

**Spanish copy never assumes the reader's gender.** Write `Te damos la bienvenida`, not
`Bienvenido` or `Bienvenida`; `colega`, not `compañero`. Reach for a gender-neutral noun or
rephrase around the adjective — never `@` or `x` endings, which screen readers mangle.
Agreement with a grammatical noun is fine and unavoidable (`Contraseña actualizada`); what
is banned is agreement with *the user*. A clinical vignette's patient has whatever gender
the case calls for; that is content, not interface.

**All user-facing text goes through i18n**, and `es.yml` / `en.yml` stay key-for-key
identical — `spec/config/locales_spec.rb` enforces it. `default_locale` is `:es`, and
`rails-i18n` supplies the Spanish for everything Rails itself emits.

**Comments explain what code cannot.** A non-obvious constraint, a decision that looks
wrong until explained, the origin of a magic value. No section dividers, no narration of
what the next line does.

## Conventions

- Double quotes. Run `bundle exec rubocop -A` on changed files after every edit.
- **Service objects**: `Namespace::Doer < ApplicationService`, one public `call`, private
  `attr_reader`. Return a `Response`; never raise for expected failure. Use the `-er` noun
  form (`Questions::Generator`), never a `-Service` suffix.
  - A service that adds an error on an attribute **must expose a reader for it** —
    `Errorable#read_attribute_for_validation` sends the attribute name to the service.
    Errors on `:base` are the only ones that need no reader.
- **String enums only**, declared with an explicit hash and a `prefix:`.
- bigint PKs. jsonb with `default: {}` / `[]`, `null: false`. Money `decimal(12,2)`,
  AI cost `decimal(12,8)`.
- Jbuilder for any JSON, never inline.
- Authorize in controllers. No Pundit, no Devise, no ViewComponent, no admin gem.

## Design

Tokens live in `app/assets/stylesheets/application.tailwind.css`. The light palette is
sampled from alan.com and each borrowed value carries an `alan:` note; dark is derived from
the same indigo ramp. Alan Sans for interface, Literata for clinical vignettes, system mono
for short strings. **Do not add a colour that is not a token**, and do not use `--highlight`
anywhere except the span of a recommendation a question was generated from.

Mobile-first, 44px minimum tap targets, every list gets loading / empty / error / populated
states. The home screen is: your average, today's plan, and a button that starts the quiz.
Nothing else above the fold — including upgrade prompts.

## The exam we are simulating

Score is a **percentage over 100**, not a weighted total — the "alta 3 / media 2 / baja 1,
560 puntos" figure in every prep blog is from the retired 450-reactivo format and the
current convocatoria does not mention difficulty at all. Difficulty *is* official and it
breaks ties: CIFRHS grades each reactivo Alta/Media/Baja and the tie-break order is Alta →
Media → Medicina Interna → Pediatría → Gineco-Obstetricia → Cirugía → total correct →
ponderación. Sources and the consequences are in the plan under "How the ENARM is actually
scored". Difficulty uses that vocabulary (`low`/`medium`/`high`), never a competitor's
Interno/Residente/Adscrito.

## The corpus is mostly expired, and that is load-bearing

CENETEC was dissolved in 2025; its successor republished only guidelines still inside
the 3–5 year validity the guidelines state for themselves, which is why the live catalog
holds nothing older than 2020. As of 2026-09 the corpus is **56 current / 539 expired**,
and **Cirugía General is 1 current of 36** — so expired guidelines cannot simply be
dropped.

`Guideline::VALIDITY_YEARS`, `.current`, `.expired`, `.undated` and `#expired?` exist for
this. An undated guideline is never expired: unknown is not the same as out of date.
**Phase 2 must prefer current guidelines and show the year on every citation.** Details
and the reasoning are in the plan under "Why the catalog shrank".

`Gpc::RefreshCatalogJob` keeps it accurate by itself, quarterly, from
`config/recurring.yml`. It costs nothing — Solid Queue runs inside Puma.

## Testing

```bash
bundle exec rspec                 # fast inner loop
bin/ci-test                       # parallel, all cores
COVERAGE=1 bin/ci-test            # + merged coverage
bin/coverage-check                # ratchet against .coverage-floor.json
bin/coverage-check --raise        # lock in an improvement, then commit the floor
```

- Request specs need an explicit `type: :request`; `infer_spec_type_from_file_location!`
  is off on purpose.
- No spec may make a live LLM call. `spec/support/llm_guard.rb` fails the suite on any
  request to a provider host.
- Coverage floor only ever moves up. It is at 99.7% line / 100% branch; keep it there.
  Prefer deleting a speculative branch to writing a spec that proves it is unreachable.
- `bundle exec rspec`, `rubocop` and `brakeman` are all green before a phase is closed.

## Gotchas already paid for

- **`json` is pinned to 2.x.** json 3.0 dropped the positional-options form of
  `JSON.parse` that `ActiveSupport::JSON.decode` still calls, which breaks encrypted
  cookie decryption on every request after the first. See the Gemfile note.
- **Never link stylesheets with `stylesheet_link_tag :app`.** The symbol form globs the
  Propshaft load path and ships the raw Tailwind source to the browser. Link
  `"application"` — the built bundle — and keep `app/assets/stylesheets` in
  `config.assets.excluded_paths`.
- **Use `bin/dev`, not `bin/rails server`.** The plain server runs no asset watcher, so
  CSS and JS changes silently do not appear.
- **`rate_limit` captures its store at class-definition time.** The test environment gives
  Action Controller a `:memory_store` of its own so limiters are testable; `rails_helper`
  clears it between examples.
- **The GPC grading strip is not a fixed grammar.** `1++ NICE Hong K, 2021` is the
  common spelling, but `SIGN D Taylor M, 2015` puts the scale first, `Muy baja GRADE …`
  has a two-word grade, and `PBP`, `C-LD` and `IIA` look like scale acronyms and are
  grades. The scale is recognised by shape, not by a list of societies — the catalog
  cites 30-odd — and `Recommendation#label` keeps the strip verbatim, so a bad split
  never loses the citation. About 11% name no scale at all; that is the authors, not us.
- **`div.separador` only means "grading strip" inside a graded section.** The anexos
  reuse it for the directory and for the tables that define the scales, so parsing
  every section manufactured 457 recommendations out of institution names. Only
  `GuidelineSection#graded?` sections are read for recommendations.
- **Sample before writing a parser, then check the whole corpus after.** Three sections
  per guideline said 1.5% of strips were unparseable; all 3,076 said 22%.
- **`deepseek-flash` thinks before answering, and the thinking is billed as output.**
  Measured live 2026-09-20 on a real generation prompt: 5,682 output tokens, of which
  **4,638 were reasoning** and 1,044 were the answer. With `max_tokens: 4000` it spent the
  entire budget thinking and returned an **empty string with `finish_reason: "length"`
  and no error** — the failure mode to fear, because it looks like success.
  Pass `thinking: {type: "disabled"}` or `reasoning_effort: "none"` and it drops to zero
  reasoning tokens and still returns valid JSON — 4.4x cheaper output. Verified against
  the API, not just the docs: `reasoning_effort: "minimal"` is silently mapped to `"low"`
  and still thinks, so it is not a way to turn this off. Gemini Flash-Lite reports zero
  reasoning tokens on the same prompt and needs none of this.
- **Gemini rejects unknown request fields; DeepSeek accepts them.** Sending `thinking`
  to Gemini's OpenAI-compatible endpoint returns 400 "Unknown name: thinking" and the
  request never runs. Provider capabilities are declared in `Llm::Provider::PRESETS`
  and `Llm::Completion` asks before sending. Do not assume a provider ignores a field
  it does not know — test it against that provider, not against the other one.
- **The `source_quote` gate normalises whitespace and case, and must.** Extraction keeps
  the source's line breaks ("se deben evitar:\nPicos hiperóxicos") and no model
  reproduces them when quoting; models also lowercase a leading "Se" to fit the quote
  into their own sentence. Measured across two unrelated model families, those two
  accounted for **every** citation rejection in the first provider comparison — the gate
  was refusing correct quotes, not catching hallucinations. Neither normalisation changes
  a word, so a paraphrase still cannot pass.
- **Tell the model not to elide.** Left to itself Gemini writes `[...]` inside a quote,
  which is honest prose and fatal to a substring check. One prompt line removes it.
- **Generation is non-deterministic, so a small sample cannot rank models.** The same
  8-guideline comparison scored Gemini 97% and then 91% on consecutive runs. At 32
  questions the confidence interval is about ±8 points: use these runs to find *defects*,
  and a much larger sample before believing any ranking.
- **Solid Queue, Cache and Cable share the primary database.** One Railway service, no
  Redis. Their tables are in `db/migrate`, not separate schemas.
