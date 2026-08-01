# Bauhaven — Brand Guidelines

## A note on this version

This replaces an earlier draft that invented a "Bauhaus" design narrative and a geometric circle/triangle/square mark neither of which came from Bauhaven's actual brand — that was a mistake, corrected once the real color values and app icon were shared. Everything below is grounded in the actual `tailwind.config` palette and the real app icon. **The mark itself is still a placeholder** (a wordmark in Montserrat) until an actual logo asset (SVG/PNG) is provided — a photo of the app icon isn't enough to redraw it accurately.

## 1. Color — the real base palette

Straight from `src/*/tailwind.config` (`theme.extend.colors.bauhaven`):

| Name | Hex |
|---|---|
| Red | `#D72638` |
| Orange | `#F26B3B` |
| Gold | `#FED500` |
| Green | `#54BE8D` |
| Blue | `#26AAD1` |
| Dark (ink) | `#1E1E1E` |
| Light (background) | `#F8F8F8` |

### Per-surface application

| Surface | Accent | Notes |
|---|---|---|
| **Site** (public) | Full palette — red as signature highlight, orange/gold/green/blue as supporting colors | Decorative use is appropriate here — marketing content, browsed briefly |
| **Admin** (internal) | Blue `#26AAD1` → Green `#54BE8D` | Functional only: primary buttons, active nav states. Both colors already exist in the real palette — no invented values |
| **Academy** (internal) | Orange `#F26B3B` → Gold `#FED500` | Same functional-only treatment |

### Semantic colors (kept distinct from decorative accents, on purpose)

| Meaning | Color | Why it's not just the brand color |
|---|---|---|
| Success | `#1B7A43` | Deliberately *not* identical to Admin's brand green (`#54BE8D`) — an "Approve" button and an "Approved" badge in the exact same green would blur CTA vs. status. Related, not identical. |
| Warning | `#8A5A00` | Muted/darker than Academy's brand gold (`#FED500`) for the same reason — a primary button and a "Pending" badge shouldn't read as the same element. |
| Danger / error | `#D72638` (the real brand red) | This one *is* the brand red directly — safe to reuse because red isn't the dominant, high-frequency accent of either Admin or Academy, so there's no CTA/status collision risk the way there would be with blue/green or orange/gold. |

**The rule going forward:** before adding any new accent color, check it against this semantic table. This is exactly the mistake this session already made once (with green) and caught before it shipped.

## 2. Typography

- **Montserrat** — display and headings.
- **Archivo** — body text and UI.
- Two faces only. Type scale: 12 (caption) · 14 (secondary) · 16 (body) · 20 (section) · 24–28 (title) · 32+ (display, Site only).

## 3. The mark — placeholder status

The real app icon is a mosaic-tile "B" monogram spanning the brand's warm-to-cool range (blue/green/orange/red). Until a source file is available:

- All wireframes use a plain **Montserrat wordmark** ("Bauhaven") in place of the mark.
- Don't recreate the mosaic icon from the phone-photo reference — its exact geometry, tile count, and proportions can't be read reliably from that image.
- Once an SVG/PNG is shared, this section gets rewritten with real usage rules (minimum size, clear space, color variants) instead of a placeholder note.

## 4. Voice & tone

- Active voice, plain verbs, no filler — a button says what it does ("Approve," "Check in now").
- Same action keeps the same name through a whole flow.
- Errors state what happened and how to fix it — never vague, never apologetic.
- Site can be a little more editorial/inviting; Admin/Academy stay direct and instructional.

## 5. Do / Don't

**Do:**
- Use the exact hex values above — they're sourced from the real config, not estimated.
- Keep semantic colors distinct from decorative accents, per the table in Section 1.
- Reserve gradients (blue→green, orange→gold) for focal moments — primary buttons, hero-style cards — not full backgrounds.

**Don't:**
- Invent palette or mark details not confirmed by an actual source (config file, brand asset, or the person's explicit direction) — this document exists because that happened once already.
- Let an accent color exactly match a semantic color.
- Introduce a third typeface.
