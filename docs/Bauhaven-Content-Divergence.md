# Content: Admin-web and the Site are two disconnected systems

**Status: nothing published in Admin-web can currently appear on bauhaven.com.** Not "is
misconfigured" — there is no path at all. This document maps what each side actually has,
so the gap can be closed deliberately rather than discovered when someone publishes a page
and nothing happens.

Found while fixing the Apply form's `applicant_id` error. That turned out to be one
symptom of the same root cause: `bauhaven-website` and `bauhaven-platform` were designed
independently and their schemas were never reconciled.

## The one-line summary

| | Admin-web writes | The Site reads |
|---|---|---|
| Tables | `pages`, `content_blocks`, `portfolio_entries` | `page_sections`, `site_settings`, `courses`, `course_levels`, `projects`, `testimonials` |
| Overlap | **none** | **none** |

Six tables on one side, three on the other, and **not one name in common**.

---

## 1. Zero table overlap

Admin-web's Content Editor writes:

| Table | Columns |
|---|---|
| `pages` | `slug`, `title_en`, `title_fr`, `body_en`, `body_fr`, `status`, `published_at` |
| `content_blocks` | `page_id`, `key`, `title_en/fr`, `body_en/fr` |
| `portfolio_entries` | `user_id`, `program_id`, `title_en/fr`, `description_en/fr`, `media_url`, `status` |

The Site reads (via `backend/src/db/schema.js`):

| Table | Shape |
|---|---|
| `site_settings` | `key` → `jsonb` blob |
| `page_sections` | `key`, `page`, `section` → `jsonb` blob |
| `courses` | `id`, `slug`, `title`, `thumbnail`, `short_description`, `long_description`, `starting_fee`, `designed_for`, `tools`, `tags` |
| `course_levels` | `course_id`, `sort_order`, `name`, `duration`, `fee`, `outline`, `outcome` |
| `projects` | `title`, `images`, `long_description`, `category`, `tags`, `year`, `client`, `team`, `live_url` |
| `testimonials` | `full_name`, `programs`, `role`, `message`, `photo`, `should_feature` |

These aren't two spellings of one model. They're two different models: the platform stores
**documents** (a page with a title and a body), the Site stores **structured content**
(a course with fees and levels, a project with images and a client).

## 2. The revalidation webhook has no receiver

`Bauhaven-Architecture-Plan.md` §5 specifies `POST /api/revalidate` with
`x-revalidate-secret`, and Admin-web implements it verbatim in `src/lib/site-revalidate.ts`.

**The Site has no `/api/revalidate` route.** No API routes at all.

That call therefore 404s. `site-revalidate.ts` deliberately never throws — so publishing
*appears to succeed*, and the only trace is a `warn` in Admin's server log. Worth knowing
that the silence is by design (a failed webhook shouldn't roll back a publish) and that it
is currently hiding a permanent failure rather than a transient one.

## 3. Two different ways into the database

- **Admin-web** → Supabase JS client + anon key → **RLS applies**.
- **The Site's content** → Drizzle over a direct `DATABASE_URL` (Postgres pooler) →
  **RLS does not apply at all.**

So even with matching tables, the Site would read straight past `status = 'published'`
unless it filtered itself. Any convergence has to decide this deliberately: either the Site
moves to the Supabase client and lets RLS gate drafts, or it keeps Drizzle and owns the
filter.

There's a third path already in the repo, and it's the reason the Site works today:
`src/lib/server/content-service.js` falls back to **static files in `src/data/`** whenever
`DATABASE_URL` is unset. The live site may well be running entirely on those files.

## 4. Bilingual on one side only

Every content column in the platform is `_en`/`_fr`, and Admin-web's Content Editor
**refuses to publish until both languages are filled in**.

The Site's schema has no French anywhere — one `title`, one `description`, one `message`.

So a perfect table mapping would still throw away half of what Admin enforces. This is the
same next-intl thread already open in the Project Brief, arriving from the content side:
the platform models a bilingual product and the public site does not.

## 5. `/portfolio` and `/blog` are built but switched off

`src/app/_portfolio/` and `src/app/_blog/` exist with full component sets — hero, list,
sidebar, CTA. The leading underscore makes Next.js ignore them, so neither is a route.

M6 ("Site: Portfolio section") assumes a `/portfolio` route reading from
`portfolio_entries`. The components are further along than the plan assumes; the data
source is the problem, not the UI.

## 6. `portfolio_entries` still has no `slug`

Already recorded as an M6 prerequisite in the Architecture Plan. Worth restating here
because the Site's own content is slug-addressed (`courses.slug`), so per-entry portfolio
routes need one for consistency as well as for revalidation.

## 7. Two env conventions inside the Site repo

- `src/lib/supabaseClient.js` (the forms) reads `NEXT_PUBLIC_SUPABASE_URL` / `NEXT_PUBLIC_SUPABASE_ANON_KEY`.
- `src/lib/server/content-service.js` (the content) reads `DATABASE_URL`.
- `.env.example` lists `DATABASE_URL`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`,
  `SUPABASE_SERVICE_ROLE_KEY` — and **not** the two `NEXT_PUBLIC_` names the forms need.

A deployment following `.env.example` gets working content and broken forms.

---

## Update: the forms are reconciled, the content is not

Since this was written, all three of the Site's forms have been brought onto the
platform's schema:

- `applications` — `010_applications_public_intake.sql`
- `contact_messages`, `website_reviews` — `011_public_site_forms.sql`, which is where they
  now exist for the first time. They had been in **no migration at all**: hand-created from
  the Site's setup doc, or never created and both forms silently failing.

`011` also declined to carry over a policy the Site's setup doc proposed —
`for select using (true)` on both tables. The anon key ships in a public marketing site's
browser bundle, so that would have let anyone read every contact message and review,
including names, emails and phone numbers given privately. Public **insert** only; reading
is Admin/Staff.

One thing worth carrying into a decision that's still open: `website_reviews` has an
`allow_public_use` consent flag, because the Site's review form asks. `testimonies` has no
such thing — consent there is the Project Brief's explicitly deferred item. **The public
site already solved the question the platform postponed**, and that column is the
precedent when it's finally settled.

**The content layer below is still entirely unreconciled.** Forms were the easy half.

## The urgent question: is it even the same database?

**This cannot be answered from the repositories, and everything above depends on it.**

`SUPABASE_SETUP.md` instructs the reader to create a Supabase project *named
`bauhaven-website`* — a second project, separate from the platform's. If the Site's
`NEXT_PUBLIC_SUPABASE_URL` points at a different project ref than Admin-web's, then:

- the Apply form now writes `applications` rows into a database **Admin-web never reads**,
  and the queue will stay empty no matter how many people apply;
- the contact and review forms are likewise isolated;
- convergence is a data migration, not a schema mapping.

**Check first, before any of the work below:** compare the project ref in the Site's
`NEXT_PUBLIC_SUPABASE_URL` against Admin-web's. Same ref → one database, and the fixes are
as described. Different refs → that is the first thing to resolve.

---

## What closing this actually takes

In dependency order. None of it is started.

| # | Work | Depends on |
|---|---|---|
| 0 | **Confirm one database** — compare project refs | — |
| 1 | **Decide who owns public content.** Either the platform absorbs courses/projects/testimonials, or the Site keeps them and Admin's editor is scoped to pages/portfolio only | 0 |
| 2 | **Add `/api/revalidate` to the Site**, per Architecture Plan §5 — header auth, both response shapes | 0 |
| 3 | **Add `slug` to `portfolio_entries`** | 0 |
| 4 | **Point the Site's portfolio at `portfolio_entries`** and un-underscore `_portfolio` | 1, 3 |
| 5 | **Reconcile bilingual content** — either the Site renders `_fr`, or the editor stops enforcing it | 1 |
| 6 | **Unify the env conventions** in the Site repo and fix `.env.example` | 0 |

**Recommendation on (1):** scope Admin's Content Editor to what the platform actually
models — pages and portfolio entries — and leave courses, projects and testimonials owned
by the Site. They are marketing content with a marketing shape (fees, tools, client names,
featured flags), and forcing them into `pages.body_en` would lose all of it. That makes
the convergence small and honest rather than a rewrite of either side.

**Not recommended:** mapping the Site's tables into the platform's document model. It
would be a lot of work to end up with less structure than either side has now.
