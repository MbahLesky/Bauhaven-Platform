# Bauhaven Platform

Shared foundation for the Bauhaven apps — planning documentation and the Supabase backend (schema, RLS, Auth, Storage). Not a standalone app; `bauhaven-admin-web` and `bauhaven-academy-web` both depend on this repo.

Originally sketched as two separate repos (docs, and a Core backend repo), combined into one here since both are shared dependencies of every app — no reason to make two repos to clone instead of one.

## Structure

```
docs/           # every planning document — start with docs/Bauhaven-Project-Brief.md
supabase/       # schema migrations, RLS policies, Supabase CLI config
```

## Start here

**New to this project?** Read `docs/Bauhaven-Project-Brief.md` first — it's the front door and links to everything else.

## Contributing — from any of the three repos

Docs here are the source of truth for `bauhaven-admin-web` and `bauhaven-academy-web` alike. If a change in either app touches something a doc describes — schema, RLS, a feature's actual behavior, a screen's structure, an API contract — update that doc **in the same commit**, not as a follow-up. Full rule and examples: `docs/Bauhaven-Coding-Standards.md`, "Documentation stays in sync."

## Supabase setup

1. Install the Supabase CLI: `npm install -g supabase`
2. `supabase init` (if not already linked), then `supabase start` — spins up local Postgres, Auth, Storage, Studio
3. Migrations in `supabase/migrations/` apply automatically on `supabase start` / `supabase db reset`
4. Both migrations are already tested against a live Postgres instance with seeded accounts — see `docs/Bauhaven-Database-Schema.md` for what was tested and the one real bug (an RLS recursion issue) that was caught and fixed along the way
5. Create a **separate Supabase project for production** — never share a database between dev and prod
6. Each web app needs `NEXT_PUBLIC_SUPABASE_URL` / `NEXT_PUBLIC_SUPABASE_ANON_KEY` pointed at this project — see that app's own `.env.example`

## Before production

- RLS policies are tested against seeded test data, not a copy of real production data — rehearse migrations against a realistic dataset before the first production deploy.
- No seed data included beyond what was used for testing — add real seed data (initial programs, admin accounts) once there's real content, not placeholder business data.
