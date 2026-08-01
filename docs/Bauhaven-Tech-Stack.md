# Bauhaven Platform — Tech Stack

Four client apps now, one backend: **Admin** (web + native) and **Academy** (web + native) each ship as two codebases sharing the same Supabase backend; **Site** stays web-only (already exists).

**Worth naming upfront:** two codebases per app means real duplicated engineering — building, testing, and keeping web and native in sync roughly doubles frontend effort per app versus a single client. RLS at the database layer keeps *authorization* logic from being duplicated (both clients defer to the same policies), but UI, forms, and offline handling still get built twice.

## Backend

- **Supabase** — Postgres 16, Auth, Storage, Realtime, already schema'd and RLS-tested.
- Separate Supabase **projects for dev and prod** — never share a database between them.
- **Supabase Storage** for profile photos, portfolio media, asset images.
- RLS is the primary authorization layer, shared by all four clients — no duplicated permission logic per platform.

## Web: Admin & Academy (Next.js)

| Concern | Choice | Why |
|---|---|---|
| Framework | **Next.js, App Router**, TypeScript, `src/` dir | Server Components fetch straight from Supabase, no separate API layer |
| Styling | **Tailwind CSS** | `dark:` class strategy, manual toggle stays possible |
| Components | **shadcn/ui** + Radix primitives | Copy-in, accessible, not a black-box dependency |
| Icons | **lucide-react** | Pairs natively with shadcn/ui |
| Animation | **Framer Motion** | Beyond what Tailwind's `transition-*`/`animate-*` covers |
| Class utilities | **clsx** / **tailwind-merge** | Conditional classes without conflicts |
| State | Local state first; Context for global (auth, locale); Zustand if needed | No Redux at this scope |
| Data fetching | Server Components, direct `async`/`await` against Supabase | No React Query/SWR unless a component needs client-side refetch |
| Forms | **react-hook-form** + **zod** | Typed validation |
| Charts | **Recharts**, via `dynamic()` import | Finance dashboards — heavy, client-only, shouldn't block render |
| i18n | **next-intl** | UI chrome; bilingual *content* already lives in `_en`/`_fr` DB columns |

## Native: Admin & Academy (Flutter)

| Concern | Choice | Why |
|---|---|---|
| Framework | **Flutter** (Dart) | One codebase for Android/iOS; matches the low-end-Android floor this platform targets |
| State management | **Riverpod** | Shop default; keeps business logic out of `build()`, in controllers/notifiers |
| Local data / offline | **Drift** (reactive SQLite) | Genuine offline-first for Academy's attendance check-in and Admin's field use — syncs to Supabase when back online, tested in-memory (`NativeDatabase.memory()`) |
| Backend client | **supabase_flutter** | Same Supabase project as the web clients — one backend, one auth session model |
| Navigation | **go_router** | Standard, deep-link-friendly Flutter routing |
| Push notifications | **Firebase Cloud Messaging** | Deadline reminders, absence-request approvals, announcements — native push is far more reliable than web push on older Android |
| i18n | **flutter_localizations** + `intl` | EN/FR UI strings, mirrors the web app's next-intl setup conceptually |
| Theming | `ThemeData` (`ColorScheme`, `TextTheme`) defined once, consumed via `Theme.of(context)` | Single source of truth, matches the web tokens |

## Testing

**Web:**
- **Vitest** + **React Testing Library** — query by role/text, not CSS class.
- **MSW** to fake Supabase calls in component tests.
- **Playwright** for the 2–3 flows that matter per app (e.g. Admin: approve a finance record; Academy: submit a task, check in attendance).

**Native:**
- **flutter_test** for widget tests on core screens; golden tests only where visuals must not drift (unlikely to matter much here — no certificates/reports in scope).
- Drift databases tested in-memory, not against a real device DB.

**Both:** every bug fix adds a test that fails without the fix. Automate levels 1–2 (business logic, data layer) near-completely; levels 3+ get a manual checklist at MVP stage.

## Tooling

- **ESLint** + **Prettier** (`prettier-plugin-tailwindcss`) for the web apps.
- **TypeScript strict mode** on both web apps.
- Flutter: standard `flutter analyze` + `dart format`.

## Hosting & distribution

| App | Where |
|---|---|
| Admin (web) | Vercel |
| Academy (web) | Vercel |
| Admin (native) | Play Store; direct APK for internal pilots |
| Academy (native) | Play Store; direct APK for pilots |
| Site | Vercel (unchanged, existing) |

Signing keys for both native apps are unrecoverable if lost — back them up offline, in two places, immediately after first generation. Separate Supabase projects for dev/prod as always; `.env.example` committed with dummies, real secrets in each host's env settings.

## Design system scope

**Real brand values, not invented ones** — this section previously referenced a made-up "Bauhaus" palette and mark; corrected once the actual `tailwind.config` colors and app icon were shared.

- **Source of truth:** `bauhaven` palette in the existing Tailwind config — Red `#D72638`, Orange `#F26B3B`, Gold `#FED500`, Green `#54BE8D`, Blue `#26AAD1`, Dark `#1E1E1E`, Light `#F8F8F8`.
- **Typography:** Montserrat (display/headings) + Archivo (body) — replaces the earlier invented Space Grotesk/Inter pairing.
- **Site (public, marketing):** full palette, decorative use appropriate for browsed-briefly marketing content.
- **Admin (internal, back-office):** **blue → green** gradient (`#26AAD1` → `#54BE8D`) for primary buttons, functional use only. Both values are the real brand colors, not invented ones.
- **Academy (internal, student-facing):** **orange → gold** gradient (`#F26B3B` → `#FED500`), same functional-only treatment.
- **Semantic colors kept distinct from decorative accents:** Success `#1B7A43` (not Admin's brand green, to avoid a button/badge collision), Warning `#8A6200` (not Academy's brand gold, same reason), Danger `#D72638` (safe to reuse the real brand red directly, since red isn't the dominant accent of either internal tool).
- **The mark:** still a placeholder (Montserrat wordmark) — the real logo is a mosaic-tile "B" icon, but no source asset (SVG/PNG) has been provided yet, only a phone photo. Don't rebuild it from that; wait for the real file.
- **Site's decorative intensity stays Site-only** — Admin/Academy use their gradient functionally (buttons, active states, a couple of hero-style cards), not as page-wide color-blocking, since these are tools used for hours at a stretch, not browsed briefly.
- Full rationale and do/don't rules: see `Bauhaven-Brand-Guidelines.md`.

## Images & media

Compress once on upload; generate serving-size variants on demand rather than storing multiple resolutions.

| Concern | Choice |
|---|---|
| Upload-side compression (web) | **browser-image-compression** — resizes/compresses client-side before hitting Supabase Storage |
| Upload-side compression (native) | **flutter_image_compress** |
| Serving-side (web) | **next/image** — automatic resize, WebP/AVIF, lazy-load; no extra tool needed |
| Serving-side (native / thumbnails) | **Supabase Storage image transforms** — resize + quality via URL params, e.g. for portfolio grid thumbnails |
| Native caching | **cached_network_image** |

## Site — unchanged

Already Next.js on Vercel. Admin's content editor feeds it via a Supabase read + the on-demand ISR revalidation webhook already scoped in the architecture plan.
