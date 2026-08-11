# Bauhaven Platform — Development Plan

## Build order

Core has to be stable first — every client app depends on it for auth and data. After that, the two web apps and two native apps are largely independent tracks (different skillsets, can run in parallel), but within each platform, Admin and Academy share enough (Supabase client setup, auth flow, design tokens) that building Admin first and lifting the shared pieces into Academy is faster than building both from scratch.

```
Core (done)
  └── Admin-web  ──┐
  └── Academy-web ─┼── share: Supabase client, auth flow, RLS-aware data fetching, brand tokens
  └── Admin-native ─┐
  └── Academy-native┴── share: Supabase client, auth flow, Riverpod provider patterns, brand tokens
```

Recommended sequence: **Admin-web → Academy-web → Admin-native → Academy-native**, on the theory that the web apps are faster to get to a working state (verified `next build` from day one) and the patterns learned there (Supabase server-client setup, RLS-aware queries, the approval-chain UI pattern) transfer directly into the native apps' repositories, even though the code itself doesn't.

## Milestones

| # | Milestone | Gate to move on |
|---|---|---|
| M0 | Core: schema + RLS | ✅ Done — tested against live Postgres with seeded accounts, one recursion bug found and fixed |
| M1 | Admin-web: scaffolded, real Supabase connection, one working screen (Dashboard) | `next build` clean, Dashboard reads real data from a dev Supabase project, auth redirect works |
| M2 | Admin-web: MVP feature set | ⚠️ **Named scope met; one open item** — Programs, Applications, Tasks, Attendance, Finance, Assets and the Content editor all ship with loading/empty/error/success states. See "M2 close-out" below |
| M3 | Academy-web: MVP feature set | ⚠️ **Every screen built; one named gate item outstanding.** Dashboard, Tasks, Attendance, Requests, Issue reporting, Testimony and Profile all ship with loading/error/success states, and Academy-web's wireframe now has no unbuilt screen. The **profile switcher** is the gap — Profile lists active roles read-only, and switching which role a session acts as still needs an "acting as" concept that doesn't exist. ~~Attendance (with offline-tolerant queue on the client)~~ — corrected during the Attendance build: web gets best-effort caching only, and the Drift-backed queue is M5's, per `Bauhaven-Architecture-Plan.md` §3. See "M3 close-out" below |
| M4 | Admin-native: MVP | Home, Approvals (finance/applications/requests), Finance, Attendance (read-mostly), Assets — matching the deliberately-scoped-down wireframe, not full Admin-web parity |
| M5 | Academy-native: MVP | Full parity with Academy-web's screens, plus real Drift-backed offline attendance check-in and FCM push for deadlines |
| M6 | Site: Portfolio section | New `/portfolio` route reading from Supabase, on-demand ISR revalidation wired to Admin's content editor |

Each milestone's exact feature list comes from the **Phase 1 (MVP)** row of the roadmap in `Bauhaven-Architecture-Plan.md` — this plan sequences that work, it doesn't redefine scope.

## Testing gates (per the priority ladder in `testing-strategy`)

Don't move a milestone to "done" without:
1. **Business logic & data layer** — near-complete unit test coverage. For this platform that's: permission-override resolution, finance approval and its append-only correction resolution, attendance excused-auto-fill from approved requests.
   *(Corrected during the Finance build: this line previously said "the finance approval-**quorum** logic". Finance has no quorum — `finance_records` carries a single `approved_by`. Quorum belongs to absence Requests, which track it in a separate `request_approvals` table. See Bauhaven-Database-Schema.md, "Two approval mechanisms, not one".)*
2. **Critical flows** — one flow test per app's core job: Admin-web (approve a finance record), Academy-web/native (submit a task, check in to attendance), Admin-native (approve from the queue).
3. **Manual checklist** at MVP stage for everything else — full automation comes with Phase 2, not before.

A bug fix without a regression test isn't done — this applies from M1 onward, not just at "maturity."

## Definition of done, per screen

- Loading, empty, error, and success states all implemented — not just the happy path.
- Checked against the 8pt spacing / contrast / touch-target rules in `Bauhaven-Coding-Standards.md`.
- EN and FR both checked — French runs 15–25% longer, and a screen that only works in English isn't done.
- RLS-backed: the screen trusts the database's authorization, it doesn't duplicate permission logic in the client.
- **Any doc this screen's behavior touches is updated in the same commit** — feature spec, wireframe, schema doc, or architecture plan, per `Bauhaven-Coding-Standards.md`'s documentation-sync rule. A screen that works but leaves its spec describing something else isn't done, it's drifted.

## M2 close-out — what shipped, and the two things that didn't

Every screen M2 names is built, each with real loading, empty, error and success states, and each RLS-backed rather than re-implementing permissions client-side. Building them surfaced four policy-vs-spec gaps that are now fixed in migrations `003`–`005`, plus one documentation error (this plan's own "finance approval-quorum" line).

**Two items are open, and neither is Phase 2 work hiding behind the roadmap:**

1. ~~**Admin's sidebar links to `/issue-reports`, which doesn't exist.**~~ **Resolved.** Feature #30 is built, alongside absence-request approvals at `/requests` — the two Staff-side halves of features Academy-web had shipped submission-only. Both are in M2's module list in spirit rather than by name, and building them here rather than deferring was the right call for the reason originally recorded: a Must feature reachable-but-missing is the worst of the three options, and Academy was by then producing rows nobody could act on.

2. **Admin's sidebar links to `/blog`, which doesn't exist and shouldn't yet.** Blog is Phase 2 by the Architecture Plan's roadmap, so *not building it* is correct — the defect is the link, not the absence. Either remove it from the nav until Phase 2 or render an explicit "coming in Phase 2" placeholder; a 404 is neither.

Both are one-line product calls rather than engineering work, which is why they're recorded here instead of being decided unilaterally during the Content Editor build.

**Also deferred, correctly, with the reasoning already written down:** Services (#6, not in M2's list), Projects and task deletion (#14/#15), Attendance's auto-excuse (blocked on Requests, a Phase 2 entity), the Application→Enrollment handoff (blocked on Invitations, likewise), financial analysis (#23, Phase 2), and per-entry portfolio revalidation (needs a `slug` column on `portfolio_entries` — an M6 prerequisite, see the Architecture Plan).


## M3 close-out — Academy-web

Every screen in `bauhaven-academy-web-wireframes.html` is built: Home, Tasks, Attendance,
Requests, Report a problem, Share feedback, Profile. Four gates clean (`tsc`, `build`,
`lint`, 167 Vitest tests).

**Three items are open, and only the first is in M3's own gate list:**

1. **The profile switcher (feature #2, Must) is still not built** — the third pass to leave
   it out, and the first to say what exists instead: Profile lists active `user_roles` rows
   read-only, with role, program and status. Switching needs somewhere to persist which
   role a session is acting as, and screens whose content actually varies by it; neither
   exists, and a dropdown that changed nothing would be worse than an honest list. It is
   the one named M3 gate item outstanding, so **M3 is not closed**.

2. **"View performance summary" (feature #12, Must) is unbuilt and isn't in M3's gate list
   either.** Aggregated grades and feedback across submissions — the data is all there
   (`submissions.grade`, `feedback`), and Academy's Tasks screen already shows both per
   task. Same class of problem as Admin's `/issue-reports`: a Must feature that no
   milestone claims. Decide whether it belongs to M3 or a milestone of its own.

3. **next-intl remains unset up across both apps.** Profile's language toggle now persists
   `users.preferred_language` for real, and the testimony form already consumes it — but
   every label in Admin-web and Academy-web is still a hard-coded English string.
   **Recommended as its own task, next**, rather than deferred a fourth time; see the
   Project Brief's "Known open items".

**Not gaps:** contact details are read-only (editing `email`/`phone` desynchronises
`public.users` from `auth.users` without a `supabase.auth.updateUser` flow), and profile
photo upload has no storage bucket to upload to. Both are recorded in the Academy Feature
Spec rather than half-built.

## What's explicitly not in scope for the MVP milestones above

Per the Architecture Plan's Phase 2/3 split: announcements/notifications polish, feedback/grading workflow refinement, blog approval flow, financial analysis dashboards, payment integration, advanced analytics, and refined asset access all come after M0–M6, not alongside them. Building them early is scope creep against an already-agreed roadmap, not a shortcut.
