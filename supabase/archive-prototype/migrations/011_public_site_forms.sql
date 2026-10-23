-- =========================================================
-- The public site's other two forms
-- =========================================================
--
-- `bauhaven-website` writes three tables. `applications` was reconciled in `010`. The
-- other two — `contact_messages` and `website_reviews` — **exist in no migration at all**.
-- They were either hand-created from the site repo's `SUPABASE_SETUP.md` (schema outside
-- version control, invisible to anyone reading these files) or never created, in which
-- case both forms have been failing.
--
-- Either way they belong here: the site is a writer, not the owner of the schema, and a
-- table nobody can find in a migration is a table nobody can reason about.
--
-- The contact form also disagreed with the site's *own* setup doc — the doc says
-- `fullname`, `inquiryType`, `message`; the code sends `name`, `tel`, `inquiry_type`,
-- `body`. That's the fifth conflicting definition found across these two repos. The
-- column names below are the platform's convention, and the form is updated to match.
--
-- ---------------------------------------------------------
-- A security note the setup doc got wrong
-- ---------------------------------------------------------
--
-- `SUPABASE_SETUP.md` proposed `create policy "Allow public select" ... using (true)` on
-- both tables, commented "for future reference". That would let **anyone holding the anon
-- key** — which ships in the browser bundle of a public marketing site, so: anyone — read
-- every contact message and every review, including names, email addresses and phone
-- numbers people gave privately.
--
-- The policies below are insert-for-anyone, read-for-staff. A public form needs exactly
-- one public capability, and it is not reading.

-- ---------------------------------------------------------
-- contact_messages
-- ---------------------------------------------------------

create table if not exists contact_messages (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  email text,
  -- Either is enough to reply; the form requires at least one, which is a form rule
  -- rather than a column rule since neither alone can be `not null`.
  phone text,
  inquiry_type text not null,
  body text not null,
  -- Read/unread rather than a workflow: nobody has designed a contact triage flow, and
  -- inventing statuses here would be inventing a feature.
  handled_at timestamptz,
  handled_by uuid references users(id),
  created_at timestamptz not null default now()
);

create index if not exists idx_contact_messages_unhandled
  on contact_messages (created_at desc) where handled_at is null;

alter table contact_messages enable row level security;

-- Anyone may write — that is what a public contact form is.
create policy contact_messages_insert_public on contact_messages
  for insert with check (true);

-- Only staff may read. See the security note above.
create policy contact_messages_select on contact_messages
  for select using (auth_is_admin_or_staff());

create policy contact_messages_update on contact_messages
  for update using (auth_is_admin_or_staff()) with check (auth_is_admin_or_staff());

-- ---------------------------------------------------------
-- website_reviews
-- ---------------------------------------------------------
--
-- **Not the same thing as `testimonies`, and deliberately a separate table.** A testimony
-- comes from an enrolled student, is written inside Academy against their account, and is
-- curated for the public site. A website review can come from anyone at all — a visitor, a
-- past client, somebody who attended one workshop — with no account and no enrolment. They
-- share a shape and nothing else; folding them together would mean either giving
-- `testimonies` a nullable `user_id` (and losing the guarantee that a testimony belongs to
-- a real student) or refusing reviews from people without accounts, which is most of them.

create table if not exists website_reviews (
  id uuid primary key default gen_random_uuid(),
  full_name text,
  email text,
  -- Free text: the site's own categories, which change with its copy. Same reasoning as
  -- `applications.program_slug` in 010.
  user_type text,
  category text,
  message text not null,
  rating integer check (rating between 1 and 5),
  /**
   * **The consent flag the site already collects.**
   *
   * Worth noting against the Project Brief's "Portfolio consent — explicitly deferred":
   * the public site asks permission before quoting somebody, and `testimonies` does not.
   * The site is ahead of the platform here, and when that deferred decision is finally
   * made this column is the precedent — not a new question.
   */
  allow_public_use boolean not null default false,
  -- Curation, mirroring `testimonies.status`. Nothing reaches the site by being submitted.
  status text not null default 'submitted' check (status in ('submitted', 'published')),
  published_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists idx_website_reviews_status
  on website_reviews (status, created_at desc);

alter table website_reviews enable row level security;

create policy website_reviews_insert_public on website_reviews
  for insert with check (true);

/**
 * Published reviews are readable by anyone — that is the point of publishing one, and the
 * public site has to be able to render them.
 *
 * The `allow_public_use` half is enforced on the **write** to `status`, not here: a review
 * can only be published by a staff member, and publishing one whose author didn't consent
 * is a decision no policy can catch after the fact. Stated so nobody assumes this arm is
 * the consent gate.
 */
create policy website_reviews_select on website_reviews
  for select using (status = 'published' or auth_is_admin_or_staff());

create policy website_reviews_curate on website_reviews
  for update using (auth_is_admin_or_staff()) with check (auth_is_admin_or_staff());

-- ---------------------------------------------------------
-- If these tables already exist by hand
-- ---------------------------------------------------------
--
-- `create table if not exists` skips silently, so a hand-created version with different
-- columns survives this migration and keeps breaking the forms. Check before assuming it
-- worked:
--
--   select table_name, column_name, data_type
--   from information_schema.columns
--   where table_name in ('contact_messages', 'website_reviews')
--   order by table_name, ordinal_position;
--
-- If the columns don't match what's above — the setup doc's `fullname` / `inquiryType`
-- being the likely case — drop the hand-made table and re-run this file. Do that only
-- after checking whether it holds real submissions worth keeping.
