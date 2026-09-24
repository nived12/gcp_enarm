# GPCEnarm

An ENARM simulator built on Mexico's public Guías de Práctica Clínica (GPC). Clinical
cases are generated from graded GPC recommendations, checked by a second model, and
every answer cites the exact recommendation it rests on, with its grade and the
guideline's year.

The interface is Spanish; the code is English. The conventions every change follows are
in [CLAUDE.md](CLAUDE.md), and deploying is in [DEPLOY.md](DEPLOY.md).

## What a student gets

- **Exams:** Quiz Express, Simulacro ENARM (exactly 280 questions, on one page, timed)
  and "Arma tu examen", always drawn as whole clinical cases.
- **Feedback:** the explanation, why each distractor is wrong, and the GPC
  recommendation the answer comes from.
- **Confidence:** "Lo sé", "Con duda" or "Adiviné", optional, marked with each answer.
- **Repaso:** missed or doubtful cases come back on an SM-2 schedule. Pearls are
  guideline statements as flashcards.
- **Plan de estudio:** a day-by-day calendar up to the exam date.
- **Stats:** average, streak, accuracy by specialty, difficulty and confidence, and
  coverage of the bank.
- **Accounts:** email and password (the email must be confirmed first) or Google. A
  14-day trial, then prepaid access through Stripe Checkout.

## Stack

Rails 8.1 · Ruby 3.3.10 · PostgreSQL · Hotwire (Turbo + Stimulus) · Tailwind CSS v4 ·
esbuild · Solid Queue / Cache / Cable · RSpec + Playwright. Mail goes through Resend,
and payments through Stripe.

## Running it locally

You need Ruby 3.3.10, Node 20.16.0 with Yarn, and PostgreSQL running locally.

```bash
bin/setup --skip-server   # gems, packages, database
cp .env.example .env      # nothing in it is required to boot
bin/dev                   # web, JS and CSS watchers, and the job worker
```

Then open http://localhost:3000.

- **Email in development:** without `RESEND_API_KEY`, nothing is sent. Every email lands
  at http://localhost:3000/letter_opener, and the "Confirma tu correo" page shows the
  link as well.
- **Use `bin/dev`, not `bin/rails server`:** emails and other background jobs need the
  worker it starts.
- **Admin:** make a user an admin from the console with
  `User.find_by(email: "...").update!(role: "admin")`. After that, roles are changed
  from `/admin/users`.

### The content

`bin/setup` seeds the specialty and topic taxonomy only. The guidelines and the question
bank come from files, not from the seeds:

```bash
bin/rails "gpc:import[path/to/guidelines.jsonl.gz]"      # the GPC corpus
bin/rails "questions:import[path/to/question-bank.jsonl.gz]"
```

To build them from scratch instead, see "Scraping from scratch" in DEPLOY.md.

## Generating questions (costs money)

The `questions:*` tasks call paid LLM APIs: a generator, and a verifier from a different
model family. **Estimate first**, which is free and makes no network calls:

```bash
bin/rails "questions:estimate[1000]"
bin/rails "questions:full_run[100,1,my-label]"   # calls, dollar cap, label (resumable)
```

`full_run` generates, backs up, verifies and publishes in chunks, and stops at the
dollar cap. `bin/rails llm:status` shows which model each role uses and which keys are
missing. `bin/rails -T questions` lists the rest.

## Tests and checks

```bash
bin/ci-test                    # the whole suite, split across CPU cores
COVERAGE=1 bin/ci-test         # the same, with a merged coverage report
bin/coverage-check             # fails below the coverage floor
bin/rubocop
bin/brakeman --no-pager
```

- The system specs drive Chromium through Playwright. Install it once with
  `npx playwright install chromium`.
- Build the assets first (`yarn build && yarn build:css`) if `bin/dev` isn't running.
- CI (`.github/workflows/ci.yml`) runs all of the above on every push.

If a page shows old JavaScript or CSS after a change, a stale `public/assets` is being
served in place of the fresh build. Run `bin/rails assets:clobber` to remove it.

## Where things live

| Path | What |
|---|---|
| `app/services/gpc/` | Reading the GPC catalog and guideline texts: live site and Wayback archive |
| `app/services/questions/` | Generating, verifying and publishing cases |
| `app/services/exams/` | Building exams, recording answers, weak spots |
| `app/services/reviews/`, `app/models/review_card.rb` | Spaced repetition (SM-2) |
| `app/services/study_plans/` | The study calendar |
| `app/services/stats/` | Average, streak, coverage, accuracy breakdowns |
| `app/services/billing/` | Stripe; the only code that may reference it |
| `app/services/identities/` | Sign-in with Google |
| `app/content/legal/` | Terms, privacy notice and refund policy (drafts) |
| `db/seeds/` | Taxonomy, topic aliases, archived guideline titles |
| `lib/tasks/` | The `gpc:*`, `questions:*` and `taxonomy:*` tasks |

## Environment

Every variable is described in [.env.example](.env.example), including the LLM keys,
Stripe, Google sign-in, Resend, Sentry and PostHog. None is required to boot. In
production they are Railway service variables; see DEPLOY.md.
