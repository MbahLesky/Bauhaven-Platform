# Bauhaven Platform — Project Brief

## What this is

Bauhaven runs programs for interns, students, holiday-makers, and staff — courses, tasks, attendance, assets, finance — and keeps a public website current. This platform replaces two earlier, inconsistent internal tools with one coherent system: a shared backend (**Core**) and four client apps built against it, plus the existing public **Site**.

This brief is the front door. Everything else referenced here already exists — read this first, then go to the specific doc for the task at hand.

## The repos, starting web-first

Three repos to start — native apps get their own repos when that track begins, not before.

| Repo | What it is | Status |
|---|---|---|
| `bauhaven-platform` | Docs + Supabase (schema, RLS, Auth, Storage). Not a standalone app — every other repo depends on it. Originally sketched as two separate repos (Core, Docs), combined here since both are shared dependencies of every app. | **Done** — schema + RLS written and tested against a live instance; all planning docs live in `docs/` |
| `bauhaven-admin-web` | Next.js — programs, applications, tasks, attendance, finance, assets, content editor, blog. Used by Admin/Staff. | **Scaffolded and verified** — `tsc`, `build`, `lint` all clean; working Dashboard querying real Supabase patterns |
| `bauhaven-academy-web` | Next.js — dashboard, tasks, attendance, requests, testimonies, profile. Used by Interns/Students/Holiday-makers. | **Scaffolded and verified**, same rigor as Admin-web |

**Deferred, not forgotten:**

| Future repo | What it will be |
|---|---|
| `bauhaven-admin-native` | Flutter — companion app scoped to approvals, finance, attendance, and asset checks in the field. Not full parity with web. |
| `bauhaven-academy-native` | Flutter — full parity with Academy-web, plus genuine offline attendance check-in and push notifications. |
| `bauhaven-site` | Already live at www.bauhaven.com, not being rebuilt — gets a new Portfolio section fed by Admin's content editor when that work starts. |

## Where everything lives

All of the following now live in `bauhaven-platform/docs/`:

| Question | Document |
|---|---|
| What does each app actually do, feature by feature? | `Bauhaven-Core-Feature-Spec.md`, `Bauhaven-Admin-Feature-Spec.md`, `Bauhaven-Academy-Feature-Spec.md` |
| How do the apps fit together, what's the connectivity/data model? | `Bauhaven-Architecture-Plan.md` (includes the Site↔Admin revalidation webhook contract) |
| What's the database schema, and how does authorization work? | `Bauhaven-Database-Schema.md` + `../supabase/migrations/001_initial_schema.sql` + `002_row_level_security.sql` |
| What libraries/frameworks does each app use? | `Bauhaven-Tech-Stack.md` |
| What are the brand colors, fonts, and rules? | `Bauhaven-Brand-Guidelines.md` |
| What should each screen look like? | `wireframes/bauhaven-admin-wireframes.html`, `wireframes/bauhaven-admin-native-wireframes.html`, `wireframes/bauhaven-academy-web-wireframes.html`, `wireframes/bauhaven-academy-native-wireframes.html`, `wireframes/bauhaven-site-portfolio-proposal.html` |
| How is work sequenced, what's the MVP? | `Bauhaven-Development-Plan.md` |
| What does each repo's folder layout look like? | `Bauhaven-Folder-Structure.md` |
| What conventions does code here follow? | `Bauhaven-Coding-Standards.md` |

## Known open items

- **Logo:** wireframes currently use a plain wordmark. The real logo (mosaic "B" icon) needs a source asset (SVG/PNG) before it can be dropped in — a phone photo isn't enough to recreate it accurately.
- **RLS re-test:** policies are tested against seeded test data, not a copy of real production data — rehearse before first production deploy.
- **Admin-native scope:** deliberately not full-parity with Admin-web (approvals/finance/attendance/assets only) — see the Admin Feature Spec's confirmed decisions section.
- **Portfolio consent — explicitly deferred:** the public Portfolio page currently publishes a student's name and project with no opt-in/consent step (Admin/Staff curation is the only gate). Deliberately pushed to a later decision, not forgotten — revisit before the Portfolio page goes live for real, since publishing real students' names and work without consent is a decision worth deliberately confirming rather than defaulting into. *(**Now covers testimonies too.** `bauhaven-academy-web` has a Share-feedback screen writing `testimonies`, which feed the same public pull-quote surface — so the same deferred decision applies to a student's own words about themselves. No consent gate was built there either, per this item. Two things sharpen it: a student cannot withdraw a testimony (`testimonies` has SELECT and INSERT policies only), and the screen states plainly that Bauhaven may feature it and that nothing publishes automatically. That statement is the closest thing to consent currently in the product.)*
- **next-intl is in the Tech Stack doc but has never been set up, in either app.** `Bauhaven-Tech-Stack.md` lists it for UI chrome, with the note that bilingual *content* lives in `_en`/`_fr` columns. The content half is handled — Admin-web's Content Editor writes both languages for pages and portfolio entries, and Academy's testimony form routes a student's words to `content_en` or `content_fr` via `users.preferred_language`. The chrome half is not: every label, button, error message and empty state across Admin-web and Academy-web is a hard-coded English string. This has now come up twice while building (Content Editor for content, Testimony for chrome) without being addressed, and every screen shipped meanwhile adds strings to extract later. Worth doing before more screens are built, since it spans both apps.

## Ground rules for anyone joining

1. Core's schema and RLS are the source of truth for what's allowed — client apps trust RLS, they don't re-implement authorization.
2. Every new screen gets checked against `ui-design-principles`-derived rules in the Coding Standards doc (spacing, contrast, all five data states) before it's called done.
3. Brand colors/fonts come from `Bauhaven-Brand-Guidelines.md` — don't introduce new ones without checking against the semantic-color table first (a real collision was caught and fixed there once already).
