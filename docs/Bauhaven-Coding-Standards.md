# Bauhaven Platform — Coding Standards

Applies across all five codebases. Goal: any file from any of the five repos should read as if it came from the same hand.

## Naming

| Thing | Convention | Example |
|---|---|---|
| Variables & functions (TS/Dart) | camelCase | `remainingBalance`, `fetchStudents()` |
| Classes, React/Flutter components | PascalCase | `ApprovalCard`, `StudentDashboard` |
| Constants | SCREAMING_SNAKE (TS), lowerCamel (Dart) | `MAX_RETRIES`, `defaultPageSize` |
| Files — React components | PascalCase matching the component | `ApprovalCard.tsx` |
| Files — `components/ui/` primitives | lowercase, as the shadcn CLI writes them — see below | `button.tsx`, `select.tsx` |
| Files — Dart | snake_case | `approval_repository.dart` |
| Files — TS utilities | kebab-case | `date-utils.ts` |
| Folders | kebab-case (web) / snake_case (Flutter) | `finance-records/`, `finance_records/` |
| DB tables & columns | plural snake_case tables, snake_case columns (already established in the schema) | `finance_records.recorded_by` |
| Git branches | `type/short-kebab` | `feature/finance-approval-queue` |
| Booleans | `is/has/can/should` prefix, positive sense | `isApproved`, not `notPending` |

**The one exception to PascalCase component files:** `components/ui/` keeps the lowercase
filenames the shadcn CLI generates. `Bauhaven-Tech-Stack.md` commits both web apps to
shadcn/ui, and `npx shadcn add dialog` writes `ui/dialog.tsx` whatever this table says —
renaming those by hand means the next `add` either reintroduces the mix or drops a
duplicate `button.tsx` next to a hand-renamed `Button.tsx`. Both web apps already have
the same lowercase `ui/` primitives, so this is the consistent state, not drift.
Everything hand-written stays PascalCase, `components/ui/` included the moment a file in
there stops being a copy-in primitive.

**The rule above all:** names describe intent, not implementation. If a name needs a comment to explain it, rename it instead. Avoid abbreviations except universal ones (`id`, `url`, `db`).

## Comments

Make code self-explanatory, then comment what code can't say — the *why*.

- **Comment:** non-obvious business rules (why finance approval needs unanimous Admin sign-off when there's more than one Admin), workarounds with a link to the issue, invariants ("`amount_minor` is always whole units — never divide here").
- **Don't comment:** what a line plainly does, commented-out code (delete it, git remembers it), change history.
- **Doc comments** on every public function/class in shared code (`lib/`, `core/`) — one sentence of purpose, params/return if non-obvious.
- Update a comment in the same edit as the code it describes — a drifted comment is worse than none.

## File & function structure

- Organize by feature, not by type, once a project exceeds a couple of screens (see `Bauhaven-Folder-Structure.md`).
- One primary thing per file. ~300 lines is a smell, not a hard rule.
- A function does one thing at one level of abstraction; extract at ~30–40 lines or when a block needs a comment header to explain itself.
- Guard clauses over nesting — return early on invalid input.
- No magic numbers — name the constant where it's defined once (e.g., `const XAF_HAS_NO_MINOR_UNIT = true;` type invariants belong in a comment near the money-handling code).
- Formatters/linters are non-negotiable: Prettier + ESLint (web), `dart format` + lints (Flutter). Never argue style a machine can settle.

## React / Next.js specifics

- Default every component to a **Server Component**. Add `"use client"` only for browser APIs, `useState`/`useEffect`, event handlers, or a client-only library — and push that boundary as far down the tree as possible.
- Fetch data directly in Server Components with `async`/`await` against the Supabase server client. Don't add React Query/SWR unless a component needs to refetch after user interaction.
- Use Server Actions for mutations instead of hand-written API routes for form submissions.
- Two component layers: **presentational** (data in, events out, no fetching) and **screen/container** (wires data to presentational trees). Most components should be presentational — they're the reusable, testable ones.
- Props: required data first, optional config after; callbacks named `onX`. A `variant` enum beats a pile of boolean flags (`isCompact`, `isMini`).
- State: local `useState`/`useReducer` first → Context only for genuinely global state (auth session, locale) → Zustand only if Context churn actually hurts. Never copy server data that a Server Component already fetched into client state — pass it down as props.

## Flutter specifics

- **Riverpod** as the default state management — compile-safe, testable without a `BuildContext`. Don't mix in a second approach.
- Split a `build()` method into separate widget classes (not private methods) once it exceeds ~80 lines or three levels of nesting — separate classes get their own `const` constructors and rebuild independently.
- Data classes stay free of Flutter imports (plain Dart, testable without a widget harness). API/database calls sit behind a repository interface.
- One `ThemeData` under `core/theme/`, built from the same brand tokens as the web apps — no hardcoded `Color(0xFF...)` inline.
- `go_router` for navigation (both native apps have well past 5 screens).
- Drift for anything that needs offline tolerance (Academy-native's attendance check-in is the primary case).

## Styling (both web apps)

- Tailwind utilities inline; extract a component once a class combination repeats 3+ times — not a CSS `@apply` abstraction.
- Class order: layout → positioning → box model → typography → visual → state variants → responsive variants. Let `prettier-plugin-tailwindcss` enforce this.
- Mobile-first: base classes for the smallest viewport (360×640 floor), layer up with `sm:`/`md:`/`lg:`.
- `dark:` class strategy, not `media` — a manual toggle should stay possible even if it's not built yet.
- **8pt spacing scale** everywhere (4, 8, 12, 16, 24, 32, 48, 64) — no arbitrary pixel values.
- Body text ≥ 16px on mobile; touch targets ≥ 48×48dp with ≥ 8dp between them.
- Every accent color gets checked against `Bauhaven-Brand-Guidelines.md`'s semantic-color table before use — this project has already caught one real collision (Admin's brand green vs. the "Approved" badge color) and fixed it; don't reintroduce that class of bug.
- Never encode meaning in color alone — pair status colors with a label or icon.

## Data states (every screen, no exceptions)

Design and implement all five: **loading** (skeletons over spinners where layout is known), **empty** (explain + point to the first action), **error** (human message + retry), **success/content**, and where relevant **offline/pending** (queued items visibly pending, never silently absent).

## Error handling & logging

1. Every failure has two audiences: the **user** gets a short, human, actionable message; the **developer** gets the full technical detail in a log. Never swap these.
2. `catch (e) {}` and ignored promise rejections are bugs, not shortcuts — catch only where you can handle, translate, or add context; otherwise let it propagate to a boundary handler (Next.js error boundary, Flutter `runZonedGuarded`).
3. Network calls anticipate timeout, no-connection, non-2xx, and malformed-body distinctly. Never auto-retry non-idempotent writes (finance records!) without an idempotency key.
4. Multi-step data changes are atomic — DB transaction, all-or-nothing.
5. User-facing message formula: **what happened + what they can do.** "No internet connection. Your check-in is saved and will sync when you're back online." — never a raw exception string. Localize every error message (EN/FR) same as any other UI text.
6. Log levels: `debug` (dev only) · `info` (expected notable events) · `warn` (handled but abnormal) · `error` (boundary caught something). Structure every entry: timestamp, level, event name, context (request/user id as UUID only).
7. **Never log:** passwords, tokens, OTPs, full payment payloads, personal data beyond IDs, full request bodies on auth endpoints.

## API & custom endpoints

Most CRUD in this platform goes straight through the Supabase client with RLS doing authorization — there's no separate Express/PHP API layer to design for most operations. This section applies to the few things that aren't plain CRUD: the content-revalidation webhook, any Server Actions with complex logic, and Edge Functions if they get added later.

- JSON envelope: `{ "data": ... }` success, `{ "error": { "code", "message", "details" } }` failure.
- snake_case field names (matches the database), ISO 8601 UTC dates, money as `{ amount_minor, currency }`.
- Never leak stack traces, SQL, or file paths in a response — log those server-side, return the envelope.
- Authorize on every request server-side — RLS handles most of this automatically, but any custom endpoint (like the revalidation webhook) still needs its own auth check (a shared secret, in that case).

## Security baseline

1. **Never trust the client.** Every check that matters happens server-side or in RLS — a decompiled Flutter build or an inspected React bundle can call the API directly.
2. RLS is the primary authorization layer for this platform — already implemented and tested. Don't duplicate permission logic in the client "for safety"; trust the policies, and if a policy is wrong, fix the policy.
3. Secrets never enter git. `.env` files ignored, `.env.example` committed with dummies. If a secret leaks: rotate first, clean up second.
4. Validate and whitelist at every boundary — explicit field whitelists on create/update (a client should never be able to set its own `role` by sending an extra field).
5. Tokens: Supabase handles JWT issuance/refresh. Store securely on mobile (`flutter_secure_storage`), never in `localStorage` on web if XSS is plausible.
6. React and Flutter escape output by default — the danger is opting out (`dangerouslySetInnerHTML`, raw HTML concatenation). Don't opt out without a specific reason and a sanitizer.

## Testing

Priority order — test where risk actually lives, not everywhere equally:

1. **Business logic & calculations** — near-complete coverage. For this platform: permission-override resolution, finance approval-quorum logic, attendance excused-auto-fill.
2. **Data layer** — repository CRUD, RLS-dependent queries (an IDOR test — can user A read user B's data — belongs here on every multi-user table).
3. **Critical user flows** — 2–3 per app (see `Bauhaven-Development-Plan.md` milestones), as component/widget or integration tests.
4. **Boundary handling** — input validation, error responses, auth checks.
5. **Everything else** — diminishing returns; don't chase coverage on presentational components with no logic.

Per stack: **Vitest + React Testing Library** (query by role/text, not CSS class) + **MSW** for the web apps; **flutter_test** + Drift in-memory databases for the native apps. Every bug fix adds a test that fails without the fix.

## Git

- Conventional Commits, lightly: `type(scope): imperative summary` — types `feat fix refactor perf docs test chore style`.
- Trunk-based: `main` always releasable, `feature/<kebab>` and `fix/<kebab>` branch from it, merged back in days not weeks.
- Never commit a broken build to `main`. Squash-merge messy branches.

## Documentation stays in sync — non-negotiable

`bauhaven-platform/docs` is the source of truth every repo defers to. When code changes something a doc describes, the doc update is **part of the same change**, not a follow-up task — matching the git-and-versioning rule that a commit is one logical change: if the summary needs "and update the docs later," it needs to happen now instead.

**What counts as doc-affecting:**
- Database schema or RLS policy changes → update `Bauhaven-Database-Schema.md` (and the migration files themselves are the schema — keep them and the doc's description of them from drifting apart)
- A feature's actual behavior diverging from its spec (scope, permissions, approval flow) → update the relevant `Bauhaven-*-Feature-Spec.md`
- A screen's real structure diverging meaningfully from its wireframe → update the wireframe HTML, not just the code
- Any API/webhook contract change (request shape, auth, error handling) → update `Bauhaven-Architecture-Plan.md`
- A new library, pattern, or convention adopted → update `Bauhaven-Tech-Stack.md` or this file

**Cross-repo consistency matters more than any single repo's correctness.** A change in `bauhaven-admin-web` that touches something Academy-web also relies on (auth flow, shared Supabase types, a brand token) isn't done until the doc describing that shared thing reflects it — check `bauhaven-platform/docs` before assuming a change is local to one repo. This project has already hit real cases of docs and code silently drifting (an RLS policy that didn't match its own spec, a webhook draft that put a secret in a query string) — both were caught by deliberately checking, not by luck.

## Pre-commit checklist

- [ ] Names read as intent; no leftover `temp`/`test2`
- [ ] No `console.log`/`print` debugging left behind
- [ ] Every catch handles, translates, or rethrows with context — no empty catches
- [ ] No secrets, keys, or credentials in the diff
- [ ] New logic covered by a test, or a justified note why not
- [ ] All five data states implemented for any new screen
- [ ] Accent colors checked against the semantic-color table
- [ ] Formatter and linter pass clean
- [ ] The diff does one thing, matching one commit message
- [ ] **If this change affects anything a doc in `bauhaven-platform/docs` describes, that doc is updated in this same commit/PR**
