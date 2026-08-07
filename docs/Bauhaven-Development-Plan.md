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
| M2 | Admin-web: MVP feature set | ⚠️ **Named scope met; two open items before M3** — Programs, Applications, Tasks, Attendance, Finance, Assets and the Content editor all ship with loading/empty/error/success states. See "M2 close-out" below |
| M3 | Academy-web: MVP feature set | Dashboard, Tasks, Attendance (with offline-tolerant queue on the client), Requests, Issue reporting, Profile switcher. **Auth is done ahead of this milestone** (login, middleware gate, sign-out, Vitest set up) — the profile switcher was deliberately excluded from that pass and remains part of this gate |
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

1. **Admin's sidebar links to `/issue-reports`, which doesn't exist.** Feature #30 ("Resolve IssueReport, routed by category", Admin/Staff, **Must**) is unbuilt. It isn't named in M2's gate list, and Phase 1 assigns issue *reporting* to Academy (M3) — but *resolving* one is Admin's job and the nav already promises it. Clicking it 404s today. Decide before M3 whether it belongs in M2's scope or moves to a milestone of its own; leaving a Must feature reachable-but-missing is the worst of the three options.

2. **Admin's sidebar links to `/blog`, which doesn't exist and shouldn't yet.** Blog is Phase 2 by the Architecture Plan's roadmap, so *not building it* is correct — the defect is the link, not the absence. Either remove it from the nav until Phase 2 or render an explicit "coming in Phase 2" placeholder; a 404 is neither.

Both are one-line product calls rather than engineering work, which is why they're recorded here instead of being decided unilaterally during the Content Editor build.

**Also deferred, correctly, with the reasoning already written down:** Services (#6, not in M2's list), Projects and task deletion (#14/#15), Attendance's auto-excuse (blocked on Requests, a Phase 2 entity), the Application→Enrollment handoff (blocked on Invitations, likewise), financial analysis (#23, Phase 2), and per-entry portfolio revalidation (needs a `slug` column on `portfolio_entries` — an M6 prerequisite, see the Architecture Plan).

## What's explicitly not in scope for the MVP milestones above

Per the Architecture Plan's Phase 2/3 split: announcements/notifications polish, feedback/grading workflow refinement, blog approval flow, financial analysis dashboards, payment integration, advanced analytics, and refined asset access all come after M0–M6, not alongside them. Building them early is scope creep against an already-agreed roadmap, not a shortcut.
