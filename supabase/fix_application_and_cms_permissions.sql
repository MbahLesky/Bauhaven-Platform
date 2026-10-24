-- =============================================================================
-- BAUHAVEN: FIX APPLICATION & CMS PERMISSIONS
-- =============================================================================
-- Copy and run this script in your Supabase Dashboard -> SQL Editor:
-- https://supabase.com/dashboard/project/keyaahfksbfigcdbbuda/sql/new
--
-- Why this is needed:
-- PostgreSQL requires table-level GRANTs before evaluating Row Level Security (RLS).
-- Earlier migration 0007 revoked UPDATE on `public.applications`, blocking ALL
-- updates from authenticated users regardless of their role. This script grants
-- the required SQL privileges and updates RLS policies so Super Admin and
-- Organisation Admins (and Application Reviewers) can decide applications and edit CMS content.
-- =============================================================================

BEGIN;

-- 1. Ensure Schema usage
GRANT USAGE ON SCHEMA public TO anon, authenticated;

-- 2. Grant table-level CRUD permissions on operational tables to authenticated
-- (RLS remains active on all tables, preserving data access boundaries)
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.applications TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.application_reviews TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.application_approvals TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.application_status_history TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.invitations TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.enrolments TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.enrolment_status_history TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.attendance_sessions TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.attendance_records TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.tasks TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.task_assignments TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.submissions TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.assets TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.page_sections TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.projects TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.testimonials TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.website_reviews TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.absence_requests TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.absence_request_approvals TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.issue_reports TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.issue_report_comments TO authenticated;

-- 3. Grant sequence permissions for SERIAL / BIGSERIAL primary keys
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO anon;

-- 4. Public submissions (anonymous visitors submitting applications or reviews)
GRANT INSERT ON TABLE public.applications TO anon;
GRANT INSERT ON TABLE public.website_reviews TO anon;

-- 5. Scope-aware RLS policy for applications:
-- Allows applications.decide, applications.review, and applications.approve
DROP POLICY IF EXISTS applications_update_decision_scoped ON public.applications;
DROP POLICY IF EXISTS applications_update_decision ON public.applications;

CREATE POLICY applications_update_decision_scoped ON public.applications
  FOR UPDATE
  USING (
    private.has_permission('applications.decide', 'offering', offering_id)
    OR private.has_permission('applications.review', 'offering', offering_id)
    OR private.has_permission('applications.approve', 'offering', offering_id)
  )
  WITH CHECK (
    private.has_permission('applications.decide', 'offering', offering_id)
    OR private.has_permission('applications.review', 'offering', offering_id)
    OR private.has_permission('applications.approve', 'offering', offering_id)
  );

-- Allow deletion of applications by governance roles
DROP POLICY IF EXISTS applications_delete_admin ON public.applications;
CREATE POLICY applications_delete_admin ON public.applications
  FOR DELETE
  USING (
    private.has_permission('applications.decide', 'offering', offering_id)
    OR private.has_permission('settings.manage')
  );

-- 6. Ensure CMS RLS policies (page_sections, projects, testimonials)
ALTER TABLE IF EXISTS public.page_sections ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.testimonials ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS page_sections_update_cms ON public.page_sections;
CREATE POLICY page_sections_update_cms ON public.page_sections
  FOR UPDATE
  USING (private.has_permission('cms.publish'))
  WITH CHECK (private.has_permission('cms.publish'));

DROP POLICY IF EXISTS projects_update_cms ON public.projects;
CREATE POLICY projects_update_cms ON public.projects
  FOR UPDATE
  USING (private.has_permission('cms.publish'))
  WITH CHECK (private.has_permission('cms.publish'));

DROP POLICY IF EXISTS projects_insert_cms ON public.projects;
CREATE POLICY projects_insert_cms ON public.projects
  FOR INSERT
  WITH CHECK (private.has_permission('cms.publish'));

DROP POLICY IF EXISTS projects_delete_cms ON public.projects;
CREATE POLICY projects_delete_cms ON public.projects
  FOR DELETE
  USING (private.has_permission('cms.publish'));

DROP POLICY IF EXISTS testimonials_update_cms ON public.testimonials;
CREATE POLICY testimonials_update_cms ON public.testimonials
  FOR UPDATE
  USING (private.has_permission('cms.publish'))
  WITH CHECK (private.has_permission('cms.publish'));

DROP POLICY IF EXISTS testimonials_insert_cms ON public.testimonials;
CREATE POLICY testimonials_insert_cms ON public.testimonials
  FOR INSERT
  WITH CHECK (private.has_permission('cms.publish'));

DROP POLICY IF EXISTS testimonials_delete_cms ON public.testimonials;
CREATE POLICY testimonials_delete_cms ON public.testimonials
  FOR DELETE
  USING (private.has_permission('cms.publish'));

COMMIT;
