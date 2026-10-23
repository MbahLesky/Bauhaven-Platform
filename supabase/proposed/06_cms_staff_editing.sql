-- =============================================================================
-- 0036_cms_staff_editing.sql (also referenced as proposed/06)
-- =============================================================================
-- Grants staff holding `cms.publish` (Super Admin, Organisation Admin, Content
-- Manager) update access to the live website content tables (`page_sections`,
-- `projects`, `testimonials`) while keeping public read access intact, and
-- ensures learners can read/insert their own feedback rows in `website_reviews`.
-- =============================================================================

alter table if exists public.page_sections enable row level security;
alter table if exists public.projects enable row level security;
alter table if exists public.testimonials enable row level security;
alter table if exists public.website_reviews enable row level security;

-- Public read policies (idempotent alongside any existing policies)
drop policy if exists page_sections_select_public on public.page_sections;
create policy page_sections_select_public on public.page_sections
  for select using (true);

drop policy if exists projects_select_public on public.projects;
create policy projects_select_public on public.projects
  for select using (true);

drop policy if exists testimonials_select_public on public.testimonials;
create policy testimonials_select_public on public.testimonials
  for select using (true);

-- Staff update policies (`cms.publish`)
drop policy if exists page_sections_update_cms on public.page_sections;
create policy page_sections_update_cms on public.page_sections
  for update
  using (private.has_permission('cms.publish'))
  with check (private.has_permission('cms.publish'));

drop policy if exists projects_update_cms on public.projects;
create policy projects_update_cms on public.projects
  for update
  using (private.has_permission('cms.publish'))
  with check (private.has_permission('cms.publish'));

drop policy if exists testimonials_update_cms on public.testimonials;
create policy testimonials_update_cms on public.testimonials
  for update
  using (private.has_permission('cms.publish'))
  with check (private.has_permission('cms.publish'));

-- website_reviews: public/learner insert, own or staff select
drop policy if exists website_reviews_insert_any on public.website_reviews;
create policy website_reviews_insert_any on public.website_reviews
  for insert
  with check (user_id is null or user_id = auth.uid());

drop policy if exists website_reviews_select_own_or_staff on public.website_reviews;
create policy website_reviews_select_own_or_staff on public.website_reviews
  for select
  using (
    user_id = auth.uid()
    or public.is_admin(auth.uid())
    or private.has_permission('cms.publish')
  );
