# Bauhaven Platform — Folder Structure

**Starting with three repos**, web-first — native apps (Admin-native, Academy-native) get their own repos later, when that track starts. Not a monorepo: `bauhaven-platform` and the two web apps have different deploy targets (a Supabase project vs. two separate Vercel sites) and different lifecycles. Repo names: kebab-case.

```
bauhaven-platform/       # shared foundation: docs + Supabase schema — both web apps depend on this
bauhaven-admin-web/
bauhaven-academy-web/
```

(Later, when the native track starts: `bauhaven-admin-native/`, `bauhaven-academy-native/` — each own repo, per the native section below.)

## `bauhaven-platform` — docs + Core, combined

Holds what both web apps depend on: the Supabase schema and every planning document. Docs and schema were originally sketched as separate repos, then combined here since both are shared dependencies of every app — no reason to make two repos to clone instead of one.

```
docs/
  Bauhaven-Project-Brief.md          # start here
  Bauhaven-Architecture-Plan.md
  Bauhaven-Core-Feature-Spec.md
  Bauhaven-Admin-Feature-Spec.md
  Bauhaven-Academy-Feature-Spec.md
  Bauhaven-Database-Schema.md
  Bauhaven-Tech-Stack.md
  Bauhaven-Brand-Guidelines.md
  Bauhaven-Development-Plan.md
  Bauhaven-Folder-Structure.md        # this file
  Bauhaven-Coding-Standards.md
  wireframes/
    bauhaven-admin-wireframes.html
    bauhaven-admin-native-wireframes.html
    bauhaven-academy-web-wireframes.html
    bauhaven-academy-native-wireframes.html
    bauhaven-site-portfolio-proposal.html
supabase/
  config.toml
  migrations/
    001_initial_schema.sql
    002_row_level_security.sql
  seed.sql              # not yet added — real seed data, not placeholder business data
.gitignore
README.md
```

## `bauhaven-admin-web` / `bauhaven-academy-web` (Next.js, App Router)

Per the `nextjs-react-conventions` standard, applied identically to both:

```
src/
  app/
    (auth)/              # route group: login, unauthenticated layout
      login/page.tsx
    (app)/                # route group: authenticated shell (sidebar/nav layout)
      layout.tsx
      dashboard/page.tsx
      programs/
        page.tsx          # list
        [id]/page.tsx      # detail
      applications/page.tsx
      tasks/page.tsx
      attendance/page.tsx
      finance/page.tsx    # Admin only
      assets/page.tsx     # Admin only
      content/page.tsx    # Admin only — the content editor
      requests/page.tsx   # Academy only
      profile/page.tsx
    layout.tsx             # root layout — fonts, providers
    globals.css            # brand tokens live here (Tailwind v4 CSS-first config)
  components/
    ui/                    # shadcn-style primitives: button, card, badge, dialog, input
    <feature>/              # e.g. finance/ApprovalCard.tsx, attendance/RosterRow.tsx
  lib/
    supabase/
      client.ts            # browser client
      server.ts            # server client (cookies-based session)
    utils.ts                # cn() and other shared helpers
  hooks/
  types/
    database.ts             # generated from the Supabase schema
public/
components.json             # shadcn config
.env.example
.gitignore
README.md
```

Colocate a component's tests next to it; only promote something into `components/ui/` once it's used in more than one feature.

## `bauhaven-admin-native` / `bauhaven-academy-native` (Flutter) — deferred

Not yet created — web comes first. Documented here so the shape is decided in advance, not improvised later.

Per the `flutter-architecture-standards` standard, organized by feature once past a couple of screens:

```
lib/
  main.dart
  app.dart                  # MaterialApp, theme, go_router setup
  core/
    theme/                  # ThemeData built from the same brand tokens as the web apps
    widgets/                 # shared widgets used across 2+ features
    utils/
    supabase/
      client.dart
  features/
    auth/
      data/
      domain/
      presentation/
        screens/
        widgets/
    approvals/               # Admin-native
      data/
      domain/
      presentation/
    finance/                  # Admin-native
    attendance/                # both
    assets/                    # Admin-native
    tasks/                      # Academy-native
    requests/                    # Academy-native
    profile/
  db/                          # Drift schema for offline-tolerant tables (attendance queue)
test/
pubspec.yaml
analysis_options.yaml
.env.example                   # or --dart-define for build-time config, per team preference
.gitignore
README.md
```

## Naming inside any of the above

Covered in full in `Bauhaven-Coding-Standards.md`; the short version: PascalCase for components/classes, camelCase for variables/functions, kebab-case folders on web / snake_case on Flutter, snake_case for Dart files.
