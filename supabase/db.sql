-- WARNING: This schema is for context only and is not meant to be run.
-- Table order and constraints may not be valid for execution.

CREATE TABLE public.application (
  application_id uuid NOT NULL DEFAULT gen_random_uuid(),
  application_reference character varying NOT NULL UNIQUE,
  full_name character varying NOT NULL,
  email character varying NOT NULL UNIQUE,
  phone_number character varying,
  program USER-DEFINED NOT NULL,
  field_of_study USER-DEFINED,
  start_date date,
  duration integer,
  status USER-DEFINED NOT NULL DEFAULT 'SUBMITTED'::application_status,
  submitted_at timestamp with time zone NOT NULL DEFAULT now(),
  reviewed_at timestamp with time zone,
  reviewed_by uuid,
  remarks text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  deleted_at timestamp with time zone,
  CONSTRAINT application_pkey PRIMARY KEY (application_id)
);
CREATE TABLE public.test_connection (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  message text NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT test_connection_pkey PRIMARY KEY (id)
);
CREATE TABLE public.contact_messages (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  sent_at timestamp with time zone NOT NULL DEFAULT now(),
  body text NOT NULL DEFAULT ''::text,
  email text,
  tel text,
  inquiry_type text NOT NULL,
  name text DEFAULT ''::text,
  sender_id text,
  CONSTRAINT contact_messages_pkey PRIMARY KEY (id)
);
CREATE TABLE public.profiles (
  id uuid NOT NULL DEFAULT auth.uid(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  full_name text NOT NULL,
  email text NOT NULL,
  phone text,
  role text NOT NULL,
  avatar_url text,
  bio text DEFAULT ''::text,
  updated_at timestamp with time zone,
  u_code text NOT NULL UNIQUE,
  status USER-DEFINED NOT NULL DEFAULT 'pending'::profile_status,
  profile_completed_at timestamp with time zone,
  CONSTRAINT profiles_pkey PRIMARY KEY (id)
);
CREATE TABLE public.applications (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  submitted_at timestamp with time zone NOT NULL DEFAULT now(),
  reference text,
  applicant_id uuid DEFAULT auth.uid(),
  program text NOT NULL,
  course text,
  level text,
  status text NOT NULL,
  message text DEFAULT ''::text,
  notes text DEFAULT ''::text,
  reviewed_at timestamp with time zone,
  full_name text,
  email text,
  phone text,
  summary text DEFAULT ''::text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  tracking_code text NOT NULL UNIQUE,
  offering_id uuid,
  applicant_profile_id uuid,
  applicant_email USER-DEFINED NOT NULL DEFAULT ''::citext,
  applicant_phone text,
  applicant_name text NOT NULL DEFAULT ''::text,
  applicant_location text,
  answers jsonb NOT NULL DEFAULT '[]'::jsonb,
  education jsonb NOT NULL DEFAULT '[]'::jsonb,
  experience jsonb NOT NULL DEFAULT '[]'::jsonb,
  links jsonb NOT NULL DEFAULT '{}'::jsonb,
  documents jsonb NOT NULL DEFAULT '[]'::jsonb,
  assigned_reviewer_id uuid,
  decision_reason text,
  duplicate_flag boolean NOT NULL DEFAULT false,
  duplicate_reason text,
  consent_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT applications_pkey PRIMARY KEY (id),
  CONSTRAINT applications_applicant_id_fkey FOREIGN KEY (applicant_id) REFERENCES public.profiles(id),
  CONSTRAINT applications_applicant_profile_id_fkey FOREIGN KEY (applicant_profile_id) REFERENCES public.profiles(id),
  CONSTRAINT applications_assigned_reviewer_id_fkey FOREIGN KEY (assigned_reviewer_id) REFERENCES public.profiles(id),
  CONSTRAINT applications_offering_id_fkey FOREIGN KEY (offering_id) REFERENCES public.offerings(id)
);
CREATE TABLE public.instruments (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  name text NOT NULL,
  CONSTRAINT instruments_pkey PRIMARY KEY (id)
);
CREATE TABLE public.website_reviews (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  full_name text,
  email text,
  user_type text NOT NULL CHECK (user_type = ANY (ARRAY['Student'::text, 'Intern'::text, 'Professional'::text, 'Parent/Guardian'::text, 'Other'::text])),
  category text NOT NULL CHECK (category = ANY (ARRAY['Overall website experience'::text, 'Courses & programs'::text, 'Internship page'::text, 'Design & layout'::text, 'Content clarity'::text, 'Performance / bugs'::text, 'Other'::text])),
  message text NOT NULL,
  rating integer CHECK (rating >= 1 AND rating <= 5),
  allow_public_use boolean DEFAULT false,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  user_id uuid DEFAULT auth.uid(),
  CONSTRAINT website_reviews_pkey PRIMARY KEY (id),
  CONSTRAINT website_feedback_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id)
);
CREATE TABLE public.course_levels (
  id integer NOT NULL DEFAULT nextval('course_levels_id_seq'::regclass),
  course_id text NOT NULL,
  sort_order integer NOT NULL,
  name text NOT NULL,
  duration text NOT NULL,
  fee text NOT NULL,
  outline jsonb NOT NULL,
  outcome jsonb NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT course_levels_pkey PRIMARY KEY (id),
  CONSTRAINT course_levels_course_id_courses_id_fk FOREIGN KEY (course_id) REFERENCES public.courses(id)
);
CREATE TABLE public.courses (
  id text NOT NULL,
  title text NOT NULL,
  slug text NOT NULL UNIQUE,
  featured boolean NOT NULL DEFAULT false,
  thumbnail text NOT NULL,
  alt_text text NOT NULL,
  short_description text NOT NULL,
  long_description text NOT NULL,
  overall_duration text NOT NULL,
  starting_fee text NOT NULL,
  designed_for jsonb NOT NULL,
  tools jsonb NOT NULL,
  tags jsonb NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT courses_pkey PRIMARY KEY (id)
);
CREATE TABLE public.page_sections (
  key text NOT NULL,
  page text NOT NULL,
  section text NOT NULL,
  data jsonb NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT page_sections_pkey PRIMARY KEY (key)
);
CREATE TABLE public.projects (
  id integer NOT NULL,
  title text NOT NULL,
  description text NOT NULL,
  images jsonb NOT NULL,
  long_description text NOT NULL,
  category text NOT NULL,
  tags jsonb NOT NULL,
  year text,
  client text,
  built_by text,
  team jsonb NOT NULL,
  tools text,
  program text,
  live_url text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT projects_pkey PRIMARY KEY (id)
);
CREATE TABLE public.site_settings (
  key text NOT NULL,
  data jsonb NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT site_settings_pkey PRIMARY KEY (key)
);
CREATE TABLE public.testimonials (
  id text NOT NULL,
  timestamp_label text,
  full_name text NOT NULL,
  programs jsonb NOT NULL,
  role text NOT NULL,
  message text NOT NULL,
  academic_level text,
  photo text,
  should_feature boolean NOT NULL DEFAULT false,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT testimonials_pkey PRIMARY KEY (id)
);
CREATE TABLE public.roles (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE,
  name text NOT NULL,
  description text NOT NULL DEFAULT ''::text,
  is_system boolean NOT NULL DEFAULT true,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  is_active boolean NOT NULL DEFAULT true,
  CONSTRAINT roles_pkey PRIMARY KEY (id)
);
CREATE TABLE public.permissions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE,
  name text NOT NULL,
  description text NOT NULL DEFAULT ''::text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  domain text,
  risk_level text CHECK ((risk_level = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text, 'critical'::text])) OR risk_level IS NULL),
  CONSTRAINT permissions_pkey PRIMARY KEY (id)
);
CREATE TABLE public.role_permissions (
  role_id uuid NOT NULL,
  permission_id uuid NOT NULL,
  created_by uuid,
  CONSTRAINT role_permissions_pkey PRIMARY KEY (role_id, permission_id),
  CONSTRAINT role_permissions_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.roles(id),
  CONSTRAINT role_permissions_permission_id_fkey FOREIGN KEY (permission_id) REFERENCES public.permissions(id),
  CONSTRAINT role_permissions_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id)
);
CREATE TABLE public.user_role_assignments (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  role_id uuid NOT NULL,
  scope_type text NOT NULL DEFAULT 'platform'::text CHECK (scope_type = ANY (ARRAY['organisation'::text, 'offering'::text, 'cohort'::text, 'project'::text, 'content_domain'::text, 'asset_domain'::text])),
  scope_id uuid,
  granted_by uuid,
  revoked_at timestamp with time zone,
  assignment_type USER-DEFINED NOT NULL DEFAULT 'permanent'::role_assignment_type,
  valid_from timestamp with time zone NOT NULL DEFAULT now(),
  valid_until timestamp with time zone,
  status USER-DEFINED NOT NULL DEFAULT 'active'::role_assignment_status,
  suspended_at timestamp with time zone,
  suspended_by uuid,
  revoked_by uuid,
  revocation_reason text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT user_role_assignments_pkey PRIMARY KEY (id),
  CONSTRAINT user_roles_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id),
  CONSTRAINT user_roles_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.roles(id),
  CONSTRAINT user_roles_granted_by_fkey FOREIGN KEY (granted_by) REFERENCES public.profiles(id),
  CONSTRAINT user_role_assignments_suspended_by_fkey FOREIGN KEY (suspended_by) REFERENCES public.profiles(id),
  CONSTRAINT user_role_assignments_revoked_by_fkey FOREIGN KEY (revoked_by) REFERENCES public.profiles(id)
);
CREATE TABLE public.offerings (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  offering_type text NOT NULL CHECK (offering_type = ANY (ARRAY['course'::text, 'bootcamp'::text, 'internship'::text, 'holiday_program'::text, 'workshop'::text, 'training'::text, 'mentorship'::text, 'program'::text])),
  title text NOT NULL,
  slug USER-DEFINED NOT NULL UNIQUE,
  publication_status USER-DEFINED NOT NULL DEFAULT 'draft'::publication_status,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  code text UNIQUE,
  short_description text,
  operational_description text,
  public_description text,
  eligibility jsonb NOT NULL DEFAULT '{}'::jsonb,
  delivery_mode text,
  location_text text,
  default_duration_text text,
  capacity integer CHECK (capacity IS NULL OR capacity > 0),
  application_opens_at timestamp with time zone,
  application_closes_at timestamp with time zone,
  is_accepting_applications boolean NOT NULL DEFAULT false,
  operational_status text NOT NULL DEFAULT 'draft'::text CHECK (operational_status = ANY (ARRAY['draft'::text, 'active'::text, 'paused'::text, 'closed'::text, 'archived'::text])),
  published_at timestamp with time zone,
  created_by uuid,
  updated_by uuid,
  summary text,
  description text,
  CONSTRAINT offerings_pkey PRIMARY KEY (id),
  CONSTRAINT offerings_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id),
  CONSTRAINT offerings_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.profiles(id)
);
CREATE TABLE public.cohorts (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  offering_id uuid NOT NULL,
  code text NOT NULL,
  name text NOT NULL,
  starts_at date,
  ends_at date,
  status text NOT NULL DEFAULT 'planned'::text CHECK (status = ANY (ARRAY['planned'::text, 'open'::text, 'active'::text, 'completed'::text, 'cancelled'::text])),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  capacity integer CHECK (capacity IS NULL OR capacity > 0),
  delivery_mode text,
  location_text text,
  closed_at timestamp with time zone,
  created_by uuid,
  updated_by uuid,
  CONSTRAINT cohorts_pkey PRIMARY KEY (id),
  CONSTRAINT cohorts_offering_id_fkey FOREIGN KEY (offering_id) REFERENCES public.offerings(id),
  CONSTRAINT cohorts_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id),
  CONSTRAINT cohorts_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.profiles(id)
);
CREATE TABLE public.application_status_history (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  application_id uuid NOT NULL,
  from_status USER-DEFINED,
  to_status USER-DEFINED NOT NULL,
  actor_id uuid,
  reason text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT application_status_history_pkey PRIMARY KEY (id),
  CONSTRAINT application_status_history_application_id_fkey FOREIGN KEY (application_id) REFERENCES public.applications(id),
  CONSTRAINT application_status_history_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES public.profiles(id)
);
CREATE TABLE public.application_reviews (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  application_id uuid NOT NULL,
  reviewer_id uuid,
  note text NOT NULL,
  recommendation text CHECK ((recommendation = ANY (ARRAY['approve'::text, 'reject'::text, 'waitlist'::text, 'request_clarification'::text])) OR recommendation IS NULL),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT application_reviews_pkey PRIMARY KEY (id),
  CONSTRAINT application_reviews_application_id_fkey FOREIGN KEY (application_id) REFERENCES public.applications(id),
  CONSTRAINT application_reviews_reviewer_id_fkey FOREIGN KEY (reviewer_id) REFERENCES public.profiles(id)
);
CREATE TABLE public.application_approvals (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  application_id uuid NOT NULL,
  decided_by uuid,
  decided_at timestamp with time zone NOT NULL DEFAULT now(),
  approved_offering_id uuid,
  approved_cohort_id uuid,
  enrolment_id uuid,
  assigned_role text NOT NULL DEFAULT 'Intern'::text,
  mentor_id uuid,
  start_date date,
  end_date date,
  CONSTRAINT application_approvals_pkey PRIMARY KEY (id),
  CONSTRAINT application_approvals_application_id_fkey FOREIGN KEY (application_id) REFERENCES public.applications(id),
  CONSTRAINT application_approvals_decided_by_fkey FOREIGN KEY (decided_by) REFERENCES public.profiles(id),
  CONSTRAINT application_approvals_approved_offering_id_fkey FOREIGN KEY (approved_offering_id) REFERENCES public.offerings(id),
  CONSTRAINT application_approvals_approved_cohort_id_fkey FOREIGN KEY (approved_cohort_id) REFERENCES public.cohorts(id),
  CONSTRAINT application_approvals_mentor_id_fkey FOREIGN KEY (mentor_id) REFERENCES public.profiles(id),
  CONSTRAINT application_approvals_enrolment_id_fkey FOREIGN KEY (enrolment_id) REFERENCES public.enrolments(id)
);
CREATE TABLE public.invitations (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  application_id uuid,
  enrolment_id uuid,
  email USER-DEFINED NOT NULL,
  token_hash text,
  status USER-DEFINED NOT NULL DEFAULT 'queued'::invitation_status,
  expires_at timestamp with time zone,
  sent_at timestamp with time zone,
  accepted_at timestamp with time zone,
  revoked_at timestamp with time zone,
  provider_message_id text,
  attempt_count integer NOT NULL DEFAULT 0,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT invitations_pkey PRIMARY KEY (id),
  CONSTRAINT invitations_application_id_fkey FOREIGN KEY (application_id) REFERENCES public.applications(id)
);
CREATE TABLE public.enrolments (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  profile_id uuid NOT NULL,
  application_id uuid,
  offering_id uuid,
  cohort_id uuid,
  assigned_role text NOT NULL DEFAULT 'Intern'::text,
  mentor_id uuid,
  status USER-DEFINED NOT NULL DEFAULT 'pending_activation'::enrolment_status,
  activated_at timestamp with time zone,
  started_at date,
  completed_at timestamp with time zone,
  withdrawn_at timestamp with time zone,
  reason text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  ends_at timestamp with time zone,
  CONSTRAINT enrolments_pkey PRIMARY KEY (id),
  CONSTRAINT enrolments_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES public.profiles(id),
  CONSTRAINT enrolments_application_id_fkey FOREIGN KEY (application_id) REFERENCES public.applications(id),
  CONSTRAINT enrolments_offering_id_fkey FOREIGN KEY (offering_id) REFERENCES public.offerings(id),
  CONSTRAINT enrolments_cohort_id_fkey FOREIGN KEY (cohort_id) REFERENCES public.cohorts(id),
  CONSTRAINT enrolments_mentor_id_fkey FOREIGN KEY (mentor_id) REFERENCES public.profiles(id)
);
CREATE TABLE public.enrolment_status_history (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  enrolment_id uuid NOT NULL,
  from_status USER-DEFINED,
  to_status USER-DEFINED NOT NULL,
  actor_id uuid,
  reason text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT enrolment_status_history_pkey PRIMARY KEY (id),
  CONSTRAINT enrolment_status_history_enrolment_id_fkey FOREIGN KEY (enrolment_id) REFERENCES public.enrolments(id),
  CONSTRAINT enrolment_status_history_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES public.profiles(id)
);
CREATE TABLE public.audit_logs (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  occurred_at timestamp with time zone NOT NULL DEFAULT now(),
  actor_id uuid,
  action text NOT NULL,
  entity_type text NOT NULL,
  entity_id text NOT NULL,
  before_data jsonb,
  after_data jsonb,
  outcome text NOT NULL DEFAULT 'success'::text CHECK (outcome = ANY (ARRAY['success'::text, 'failure'::text])),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  request_id uuid,
  CONSTRAINT audit_logs_pkey PRIMARY KEY (id),
  CONSTRAINT audit_logs_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES public.profiles(id)
);
CREATE TABLE public.idempotency_keys (
  key text NOT NULL,
  operation text NOT NULL,
  actor_id uuid,
  request_hash text,
  status text NOT NULL DEFAULT 'processing'::text CHECK (status = ANY (ARRAY['processing'::text, 'completed'::text, 'failed'::text])),
  response jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  expires_at timestamp with time zone NOT NULL DEFAULT (now() + '24:00:00'::interval),
  CONSTRAINT idempotency_keys_pkey PRIMARY KEY (key),
  CONSTRAINT idempotency_keys_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES public.profiles(id)
);
CREATE TABLE public.role_assignment_events (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  assignment_id uuid NOT NULL,
  event_type text NOT NULL CHECK (event_type = ANY (ARRAY['granted'::text, 'activated'::text, 'extended'::text, 'suspended'::text, 'reinstated'::text, 'expired'::text, 'revoked'::text])),
  actor_id uuid,
  occurred_at timestamp with time zone NOT NULL DEFAULT now(),
  reason text,
  previous_values jsonb,
  new_values jsonb,
  CONSTRAINT role_assignment_events_pkey PRIMARY KEY (id),
  CONSTRAINT role_assignment_events_assignment_id_fkey FOREIGN KEY (assignment_id) REFERENCES public.user_role_assignments(id),
  CONSTRAINT role_assignment_events_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES public.profiles(id)
);
CREATE TABLE public.admin_invitations (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  email USER-DEFINED NOT NULL,
  role_id uuid NOT NULL,
  assignment_type USER-DEFINED NOT NULL,
  scope_type text NOT NULL CHECK (scope_type = ANY (ARRAY['organisation'::text, 'offering'::text, 'cohort'::text, 'project'::text, 'content_domain'::text, 'asset_domain'::text])),
  scope_id uuid,
  access_valid_from timestamp with time zone NOT NULL DEFAULT now(),
  access_valid_until timestamp with time zone,
  token_hash text NOT NULL UNIQUE,
  status USER-DEFINED NOT NULL DEFAULT 'queued'::invitation_status,
  issued_by uuid,
  issued_at timestamp with time zone NOT NULL DEFAULT now(),
  expires_at timestamp with time zone NOT NULL,
  accepted_at timestamp with time zone,
  accepted_user_id uuid,
  revoked_at timestamp with time zone,
  revoked_by uuid,
  delivery_status text,
  provider_message_id text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT admin_invitations_pkey PRIMARY KEY (id),
  CONSTRAINT admin_invitations_revoked_by_fkey FOREIGN KEY (revoked_by) REFERENCES public.profiles(id),
  CONSTRAINT admin_invitations_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.roles(id),
  CONSTRAINT admin_invitations_issued_by_fkey FOREIGN KEY (issued_by) REFERENCES public.profiles(id),
  CONSTRAINT admin_invitations_accepted_user_id_fkey FOREIGN KEY (accepted_user_id) REFERENCES public.profiles(id)
);
CREATE TABLE public.staff_profiles (
  profile_id uuid NOT NULL,
  staff_code text UNIQUE,
  job_title text,
  department text,
  staff_type text CHECK ((staff_type = ANY (ARRAY['permanent'::text, 'temporary'::text, 'contractor'::text])) OR staff_type IS NULL),
  start_date date,
  end_date date,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT staff_profiles_pkey PRIMARY KEY (profile_id),
  CONSTRAINT staff_profiles_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES public.profiles(id)
);
CREATE TABLE public.access_reviews (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  assignment_id uuid NOT NULL,
  reviewed_by uuid,
  reviewed_at timestamp with time zone NOT NULL DEFAULT now(),
  decision text NOT NULL CHECK (decision = ANY (ARRAY['retain'::text, 'extend'::text, 'suspend'::text, 'revoke'::text])),
  new_valid_until timestamp with time zone,
  notes text,
  CONSTRAINT access_reviews_pkey PRIMARY KEY (id),
  CONSTRAINT access_reviews_assignment_id_fkey FOREIGN KEY (assignment_id) REFERENCES public.user_role_assignments(id),
  CONSTRAINT access_reviews_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES public.profiles(id)
);
CREATE TABLE public.cohort_staff_assignments (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  cohort_id uuid NOT NULL,
  staff_profile_id uuid NOT NULL,
  responsibility text NOT NULL CHECK (responsibility = ANY (ARRAY['manager'::text, 'coordinator'::text, 'mentor'::text, 'reviewer'::text, 'instructor'::text])),
  starts_at timestamp with time zone NOT NULL DEFAULT now(),
  ends_at timestamp with time zone,
  created_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT cohort_staff_assignments_pkey PRIMARY KEY (id),
  CONSTRAINT cohort_staff_assignments_cohort_id_fkey FOREIGN KEY (cohort_id) REFERENCES public.cohorts(id),
  CONSTRAINT cohort_staff_assignments_staff_profile_id_fkey FOREIGN KEY (staff_profile_id) REFERENCES public.profiles(id),
  CONSTRAINT cohort_staff_assignments_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id)
);
CREATE TABLE public.programme_milestones (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  offering_id uuid,
  cohort_id uuid,
  title text NOT NULL,
  description text,
  due_at timestamp with time zone,
  sort_order integer NOT NULL DEFAULT 0,
  is_visible_to_participants boolean NOT NULL DEFAULT true,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT programme_milestones_pkey PRIMARY KEY (id),
  CONSTRAINT programme_milestones_offering_id_fkey FOREIGN KEY (offering_id) REFERENCES public.offerings(id),
  CONSTRAINT programme_milestones_cohort_id_fkey FOREIGN KEY (cohort_id) REFERENCES public.cohorts(id)
);
CREATE TABLE public.participant_profiles (
  profile_id uuid NOT NULL,
  date_of_birth date,
  gender text,
  address_text text,
  city text,
  country_code text,
  education_level text,
  institution_name text,
  emergency_contact_name text,
  emergency_contact_phone text,
  bio text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT participant_profiles_pkey PRIMARY KEY (profile_id),
  CONSTRAINT participant_profiles_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES public.profiles(id)
);
CREATE TABLE public.super_admin_bootstrap_state (
  singleton boolean NOT NULL DEFAULT true CHECK (singleton),
  used_at timestamp with time zone NOT NULL DEFAULT now(),
  used_for_email USER-DEFINED NOT NULL,
  created_assignment_id uuid,
  CONSTRAINT super_admin_bootstrap_state_pkey PRIMARY KEY (singleton)
);
CREATE TABLE public.learning_projects (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  offering_id uuid,
  cohort_id uuid,
  title text NOT NULL,
  description text NOT NULL DEFAULT ''::text,
  status text NOT NULL DEFAULT 'draft'::text CHECK (status = ANY (ARRAY['draft'::text, 'active'::text, 'completed'::text, 'archived'::text])),
  starts_at timestamp with time zone,
  ends_at timestamp with time zone,
  created_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT learning_projects_pkey PRIMARY KEY (id),
  CONSTRAINT learning_projects_offering_id_fkey FOREIGN KEY (offering_id) REFERENCES public.offerings(id),
  CONSTRAINT learning_projects_cohort_id_fkey FOREIGN KEY (cohort_id) REFERENCES public.cohorts(id),
  CONSTRAINT learning_projects_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id)
);
CREATE TABLE public.tasks (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  offering_id uuid,
  cohort_id uuid,
  project_id uuid,
  title text NOT NULL,
  instructions text NOT NULL DEFAULT ''::text,
  status USER-DEFINED NOT NULL DEFAULT 'draft'::task_status,
  starts_at timestamp with time zone,
  due_at timestamp with time zone,
  submission_type text NOT NULL DEFAULT 'text'::text CHECK (submission_type = ANY (ARRAY['text'::text, 'file'::text, 'link'::text, 'mixed'::text, 'none'::text])),
  allowed_file_rules jsonb NOT NULL DEFAULT '{}'::jsonb,
  resources jsonb NOT NULL DEFAULT '[]'::jsonb,
  allow_resubmission boolean NOT NULL DEFAULT false,
  max_resubmissions integer,
  rubric_response_template jsonb,
  created_by uuid,
  published_at timestamp with time zone,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT tasks_pkey PRIMARY KEY (id),
  CONSTRAINT tasks_offering_id_fkey FOREIGN KEY (offering_id) REFERENCES public.offerings(id),
  CONSTRAINT tasks_cohort_id_fkey FOREIGN KEY (cohort_id) REFERENCES public.cohorts(id),
  CONSTRAINT tasks_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.learning_projects(id),
  CONSTRAINT tasks_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id)
);
CREATE TABLE public.task_assignments (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  task_id uuid NOT NULL,
  enrolment_id uuid NOT NULL,
  assigned_by uuid,
  assigned_at timestamp with time zone NOT NULL DEFAULT now(),
  due_at_override timestamp with time zone,
  reviewer_id uuid,
  status USER-DEFINED NOT NULL DEFAULT 'assigned'::assignment_status,
  completed_at timestamp with time zone,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT task_assignments_pkey PRIMARY KEY (id),
  CONSTRAINT task_assignments_task_id_fkey FOREIGN KEY (task_id) REFERENCES public.tasks(id),
  CONSTRAINT task_assignments_enrolment_id_fkey FOREIGN KEY (enrolment_id) REFERENCES public.enrolments(id),
  CONSTRAINT task_assignments_assigned_by_fkey FOREIGN KEY (assigned_by) REFERENCES public.profiles(id),
  CONSTRAINT task_assignments_reviewer_id_fkey FOREIGN KEY (reviewer_id) REFERENCES public.profiles(id)
);
CREATE TABLE public.submissions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  task_assignment_id uuid NOT NULL,
  participant_id uuid NOT NULL,
  version_number integer NOT NULL DEFAULT 1,
  status USER-DEFINED NOT NULL DEFAULT 'draft'::submission_status,
  text_content text,
  link_url text,
  files jsonb NOT NULL DEFAULT '[]'::jsonb,
  submitted_at timestamp with time zone,
  is_late boolean NOT NULL DEFAULT false,
  idempotency_key text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT submissions_pkey PRIMARY KEY (id),
  CONSTRAINT submissions_task_assignment_id_fkey FOREIGN KEY (task_assignment_id) REFERENCES public.task_assignments(id),
  CONSTRAINT submissions_participant_id_fkey FOREIGN KEY (participant_id) REFERENCES public.profiles(id)
);
CREATE TABLE public.feedback (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  submission_id uuid NOT NULL,
  reviewer_id uuid NOT NULL,
  visible_feedback text,
  private_note text,
  result text CHECK ((result = ANY (ARRAY['accepted'::text, 'changes_requested'::text, 'completed'::text, 'approved'::text])) OR result IS NULL),
  score numeric,
  rubric_response jsonb,
  visibility USER-DEFINED NOT NULL DEFAULT 'private'::feedback_visibility,
  allow_resubmission boolean NOT NULL DEFAULT false,
  resubmission_due_at timestamp with time zone,
  released_at timestamp with time zone,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT feedback_pkey PRIMARY KEY (id),
  CONSTRAINT feedback_submission_id_fkey FOREIGN KEY (submission_id) REFERENCES public.submissions(id),
  CONSTRAINT feedback_reviewer_id_fkey FOREIGN KEY (reviewer_id) REFERENCES public.profiles(id)
);
CREATE TABLE public.finance_fee_plans (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  offering_id uuid,
  cohort_id uuid,
  name text NOT NULL,
  description text,
  currency text NOT NULL DEFAULT 'XAF'::text,
  base_amount numeric NOT NULL CHECK (base_amount >= 0::numeric),
  due_date date,
  allows_installments boolean NOT NULL DEFAULT true,
  status text NOT NULL DEFAULT 'active'::text CHECK (status = ANY (ARRAY['draft'::text, 'active'::text, 'archived'::text])),
  created_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT finance_fee_plans_pkey PRIMARY KEY (id),
  CONSTRAINT finance_fee_plans_offering_id_fkey FOREIGN KEY (offering_id) REFERENCES public.offerings(id),
  CONSTRAINT finance_fee_plans_cohort_id_fkey FOREIGN KEY (cohort_id) REFERENCES public.cohorts(id),
  CONSTRAINT finance_fee_plans_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id)
);
CREATE TABLE public.finance_participant_charges (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  enrolment_id uuid,
  legacy_participant_id uuid,
  fee_plan_id uuid,
  description text NOT NULL DEFAULT ''::text,
  currency text NOT NULL DEFAULT 'XAF'::text,
  original_amount numeric NOT NULL CHECK (original_amount >= 0::numeric),
  discount_amount numeric NOT NULL DEFAULT 0 CHECK (discount_amount >= 0::numeric),
  waiver_amount numeric NOT NULL DEFAULT 0 CHECK (waiver_amount >= 0::numeric),
  amount_due numeric NOT NULL CHECK (amount_due >= 0::numeric),
  due_date date,
  status text NOT NULL DEFAULT 'draft'::text CHECK (status = ANY (ARRAY['draft'::text, 'active'::text, 'partially_paid'::text, 'paid'::text, 'overdue'::text, 'waived'::text, 'cancelled'::text])),
  source_system text NOT NULL DEFAULT 'bauhaven_admin'::text CHECK (source_system = ANY (ARRAY['bauhaven_admin'::text, 'bauhaven_ft'::text])),
  source_id text,
  created_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT finance_participant_charges_pkey PRIMARY KEY (id),
  CONSTRAINT finance_participant_charges_enrolment_id_fkey FOREIGN KEY (enrolment_id) REFERENCES public.enrolments(id),
  CONSTRAINT finance_participant_charges_fee_plan_id_fkey FOREIGN KEY (fee_plan_id) REFERENCES public.finance_fee_plans(id),
  CONSTRAINT finance_participant_charges_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id)
);
CREATE TABLE public.finance_payments (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  payer_profile_id uuid,
  legacy_participant_id uuid,
  currency text NOT NULL DEFAULT 'XAF'::text,
  amount numeric NOT NULL CHECK (amount > 0::numeric),
  payment_date timestamp with time zone NOT NULL DEFAULT now(),
  payment_method text NOT NULL CHECK (payment_method = ANY (ARRAY['cash'::text, 'mtn_momo'::text, 'orange_money'::text, 'bank_transfer'::text, 'other'::text])),
  external_reference text,
  internal_reference text NOT NULL DEFAULT finance_generate_payment_reference() UNIQUE,
  status text NOT NULL DEFAULT 'pending'::text CHECK (status = ANY (ARRAY['pending'::text, 'confirmed'::text, 'failed'::text, 'reversed'::text, 'refunded'::text, 'cancelled'::text])),
  notes text,
  source_system text NOT NULL DEFAULT 'bauhaven_admin'::text CHECK (source_system = ANY (ARRAY['bauhaven_admin'::text, 'bauhaven_ft'::text])),
  source_id text,
  recorded_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT finance_payments_pkey PRIMARY KEY (id),
  CONSTRAINT finance_payments_payer_profile_id_fkey FOREIGN KEY (payer_profile_id) REFERENCES public.profiles(id),
  CONSTRAINT finance_payments_recorded_by_fkey FOREIGN KEY (recorded_by) REFERENCES public.profiles(id)
);
CREATE TABLE public.finance_payment_allocations (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  payment_id uuid NOT NULL,
  charge_id uuid NOT NULL,
  allocated_amount numeric NOT NULL CHECK (allocated_amount > 0::numeric),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT finance_payment_allocations_pkey PRIMARY KEY (id),
  CONSTRAINT finance_payment_allocations_payment_id_fkey FOREIGN KEY (payment_id) REFERENCES public.finance_payments(id),
  CONSTRAINT finance_payment_allocations_charge_id_fkey FOREIGN KEY (charge_id) REFERENCES public.finance_participant_charges(id)
);
CREATE TABLE public.finance_receipts (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  payment_id uuid NOT NULL UNIQUE,
  receipt_number text NOT NULL DEFAULT finance_generate_receipt_number() UNIQUE,
  issued_at timestamp with time zone NOT NULL DEFAULT now(),
  issued_by uuid,
  document_path text,
  verification_code text NOT NULL DEFAULT encode(gen_random_bytes(9), 'hex'::text) UNIQUE,
  status text NOT NULL DEFAULT 'issued'::text CHECK (status = ANY (ARRAY['issued'::text, 'void'::text])),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT finance_receipts_pkey PRIMARY KEY (id),
  CONSTRAINT finance_receipts_payment_id_fkey FOREIGN KEY (payment_id) REFERENCES public.finance_payments(id),
  CONSTRAINT finance_receipts_issued_by_fkey FOREIGN KEY (issued_by) REFERENCES public.profiles(id)
);
CREATE TABLE public.finance_payment_accounts (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  name text NOT NULL,
  code text NOT NULL UNIQUE,
  currency text NOT NULL DEFAULT 'XAF'::text,
  current_balance numeric NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT true,
  legacy_id uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT finance_payment_accounts_pkey PRIMARY KEY (id)
);
CREATE TABLE public.finance_expense_categories (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE,
  name text NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  CONSTRAINT finance_expense_categories_pkey PRIMARY KEY (id)
);
CREATE TABLE public.finance_income (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  source text NOT NULL,
  charge_id uuid,
  payment_account_id uuid,
  description text NOT NULL DEFAULT ''::text,
  currency text NOT NULL DEFAULT 'XAF'::text,
  amount numeric NOT NULL CHECK (amount >= 0::numeric),
  approval_status text NOT NULL DEFAULT 'pending'::text CHECK (approval_status = ANY (ARRAY['pending'::text, 'confirmed'::text, 'voided'::text, 'self_approved_flagged'::text])),
  void_reason text,
  entered_by uuid,
  approved_by uuid,
  voided_by uuid,
  legacy_id uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  transaction_date date NOT NULL DEFAULT CURRENT_DATE,
  approved_at timestamp with time zone,
  voided_at timestamp with time zone,
  override_reason text,
  payment_method text NOT NULL DEFAULT 'cash'::text CHECK (payment_method = ANY (ARRAY['cash'::text, 'mtn_momo'::text, 'orange_money'::text, 'bank_transfer'::text, 'other'::text])),
  CONSTRAINT finance_income_pkey PRIMARY KEY (id),
  CONSTRAINT finance_income_charge_id_fkey FOREIGN KEY (charge_id) REFERENCES public.finance_participant_charges(id),
  CONSTRAINT finance_income_payment_account_id_fkey FOREIGN KEY (payment_account_id) REFERENCES public.finance_payment_accounts(id),
  CONSTRAINT finance_income_entered_by_fkey FOREIGN KEY (entered_by) REFERENCES public.profiles(id),
  CONSTRAINT finance_income_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES public.profiles(id),
  CONSTRAINT finance_income_voided_by_fkey FOREIGN KEY (voided_by) REFERENCES public.profiles(id)
);
CREATE TABLE public.finance_expenses (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  category_id uuid,
  custom_category text,
  description text NOT NULL DEFAULT ''::text,
  currency text NOT NULL DEFAULT 'XAF'::text,
  amount numeric NOT NULL CHECK (amount >= 0::numeric),
  payment_method text,
  payment_account_id uuid,
  person_in_charge text,
  approval_status text NOT NULL DEFAULT 'pending'::text CHECK (approval_status = ANY (ARRAY['pending'::text, 'confirmed'::text, 'voided'::text, 'self_approved_flagged'::text])),
  void_reason text,
  entered_by uuid,
  approved_by uuid,
  voided_by uuid,
  legacy_id uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  transaction_date date NOT NULL DEFAULT CURRENT_DATE,
  approved_at timestamp with time zone,
  voided_at timestamp with time zone,
  override_reason text,
  CONSTRAINT finance_expenses_pkey PRIMARY KEY (id),
  CONSTRAINT finance_expenses_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.finance_expense_categories(id),
  CONSTRAINT finance_expenses_payment_account_id_fkey FOREIGN KEY (payment_account_id) REFERENCES public.finance_payment_accounts(id),
  CONSTRAINT finance_expenses_entered_by_fkey FOREIGN KEY (entered_by) REFERENCES public.profiles(id),
  CONSTRAINT finance_expenses_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES public.profiles(id),
  CONSTRAINT finance_expenses_voided_by_fkey FOREIGN KEY (voided_by) REFERENCES public.profiles(id)
);
CREATE TABLE public.finance_loans (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  person_name text NOT NULL,
  person_phone text,
  amount_borrowed numeric NOT NULL CHECK (amount_borrowed >= 0::numeric),
  date_borrowed timestamp with time zone NOT NULL DEFAULT now(),
  deadline timestamp with time zone,
  status text NOT NULL DEFAULT 'active'::text CHECK (status = ANY (ARRAY['active'::text, 'repaid'::text, 'written_off'::text])),
  notes text,
  created_by uuid,
  legacy_id uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT finance_loans_pkey PRIMARY KEY (id),
  CONSTRAINT finance_loans_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id)
);
CREATE TABLE public.finance_loan_repayments (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  loan_id uuid NOT NULL,
  amount numeric NOT NULL CHECK (amount > 0::numeric),
  repaid_at timestamp with time zone NOT NULL DEFAULT now(),
  recorded_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  payment_method text,
  CONSTRAINT finance_loan_repayments_pkey PRIMARY KEY (id),
  CONSTRAINT finance_loan_repayments_loan_id_fkey FOREIGN KEY (loan_id) REFERENCES public.finance_loans(id),
  CONSTRAINT finance_loan_repayments_recorded_by_fkey FOREIGN KEY (recorded_by) REFERENCES public.profiles(id)
);
CREATE TABLE public.finance_budgets (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  month integer NOT NULL CHECK (month >= 1 AND month <= 12),
  year integer NOT NULL,
  income_targets jsonb NOT NULL DEFAULT '{}'::jsonb,
  expense_targets jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_by uuid,
  legacy_id uuid,
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT finance_budgets_pkey PRIMARY KEY (id),
  CONSTRAINT finance_budgets_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id)
);
CREATE TABLE public.finance_invoices (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  invoice_number text NOT NULL UNIQUE,
  charge_id uuid,
  client_name text NOT NULL,
  client_email text,
  client_phone text,
  currency text NOT NULL DEFAULT 'XAF'::text,
  total_amount numeric NOT NULL CHECK (total_amount >= 0::numeric),
  due_date date,
  status text NOT NULL DEFAULT 'draft'::text CHECK (status = ANY (ARRAY['draft'::text, 'sent'::text, 'paid'::text, 'overdue'::text, 'cancelled'::text])),
  document_path text,
  created_by uuid,
  legacy_id uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  paid_date timestamp with time zone,
  void_reason text,
  voided_by uuid,
  CONSTRAINT finance_invoices_pkey PRIMARY KEY (id),
  CONSTRAINT finance_invoices_charge_id_fkey FOREIGN KEY (charge_id) REFERENCES public.finance_participant_charges(id),
  CONSTRAINT finance_invoices_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id),
  CONSTRAINT finance_invoices_voided_by_fkey FOREIGN KEY (voided_by) REFERENCES public.profiles(id)
);
CREATE TABLE public.finance_invoice_items (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  invoice_id uuid NOT NULL,
  description text NOT NULL,
  quantity integer NOT NULL DEFAULT 1 CHECK (quantity > 0),
  unit_amount numeric NOT NULL CHECK (unit_amount >= 0::numeric),
  sort_order integer NOT NULL DEFAULT 0,
  CONSTRAINT finance_invoice_items_pkey PRIMARY KEY (id),
  CONSTRAINT finance_invoice_items_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES public.finance_invoices(id)
);
CREATE TABLE public.finance_petty_cash_entries (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  entry_type text NOT NULL CHECK (entry_type = ANY (ARRAY['in'::text, 'out'::text])),
  description text NOT NULL DEFAULT ''::text,
  currency text NOT NULL DEFAULT 'XAF'::text,
  amount numeric NOT NULL CHECK (amount > 0::numeric),
  running_balance numeric NOT NULL,
  linked_expense_id uuid,
  linked_income_id uuid,
  entered_by uuid,
  legacy_id uuid,
  entry_date timestamp with time zone NOT NULL DEFAULT now(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT finance_petty_cash_entries_pkey PRIMARY KEY (id),
  CONSTRAINT finance_petty_cash_entries_linked_expense_id_fkey FOREIGN KEY (linked_expense_id) REFERENCES public.finance_expenses(id),
  CONSTRAINT finance_petty_cash_entries_linked_income_id_fkey FOREIGN KEY (linked_income_id) REFERENCES public.finance_income(id),
  CONSTRAINT finance_petty_cash_entries_entered_by_fkey FOREIGN KEY (entered_by) REFERENCES public.profiles(id)
);
CREATE TABLE public.finance_transaction_events (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  event_type text NOT NULL,
  entity_type text NOT NULL,
  entity_id uuid NOT NULL,
  actor_id uuid,
  before_data jsonb,
  after_data jsonb,
  source_system text NOT NULL DEFAULT 'bauhaven_admin'::text CHECK (source_system = ANY (ARRAY['bauhaven_admin'::text, 'bauhaven_ft'::text])),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT finance_transaction_events_pkey PRIMARY KEY (id),
  CONSTRAINT finance_transaction_events_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES public.profiles(id)
);
CREATE TABLE public.ft_import_participants (
  legacy_id uuid NOT NULL,
  raw jsonb NOT NULL,
  imported_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT ft_import_participants_pkey PRIMARY KEY (legacy_id)
);
CREATE TABLE public.ft_import_users (
  legacy_id uuid NOT NULL,
  raw jsonb NOT NULL,
  imported_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT ft_import_users_pkey PRIMARY KEY (legacy_id)
);
CREATE TABLE public.ft_import_income (
  legacy_id uuid NOT NULL,
  raw jsonb NOT NULL,
  imported_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT ft_import_income_pkey PRIMARY KEY (legacy_id)
);
CREATE TABLE public.ft_import_expenses (
  legacy_id uuid NOT NULL,
  raw jsonb NOT NULL,
  imported_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT ft_import_expenses_pkey PRIMARY KEY (legacy_id)
);
CREATE TABLE public.ft_import_loans (
  legacy_id uuid NOT NULL,
  raw jsonb NOT NULL,
  imported_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT ft_import_loans_pkey PRIMARY KEY (legacy_id)
);
CREATE TABLE public.ft_import_payment_accounts (
  legacy_id uuid NOT NULL,
  raw jsonb NOT NULL,
  imported_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT ft_import_payment_accounts_pkey PRIMARY KEY (legacy_id)
);
CREATE TABLE public.ft_import_budgets (
  legacy_id uuid NOT NULL,
  raw jsonb NOT NULL,
  imported_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT ft_import_budgets_pkey PRIMARY KEY (legacy_id)
);
CREATE TABLE public.ft_import_invoices (
  legacy_id uuid NOT NULL,
  raw jsonb NOT NULL,
  imported_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT ft_import_invoices_pkey PRIMARY KEY (legacy_id)
);
CREATE TABLE public.ft_import_petty_cash (
  legacy_id uuid NOT NULL,
  raw jsonb NOT NULL,
  imported_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT ft_import_petty_cash_pkey PRIMARY KEY (legacy_id)
);
CREATE TABLE public.ft_import_attendance (
  legacy_id uuid NOT NULL,
  raw jsonb NOT NULL,
  imported_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT ft_import_attendance_pkey PRIMARY KEY (legacy_id)
);
CREATE TABLE public.ft_import_audit_log (
  legacy_id uuid NOT NULL,
  raw jsonb NOT NULL,
  imported_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT ft_import_audit_log_pkey PRIMARY KEY (legacy_id)
);
CREATE TABLE public.integration_ft_id_map (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  source_table text NOT NULL,
  legacy_id uuid NOT NULL,
  target_table text NOT NULL,
  target_id uuid NOT NULL,
  match_method text NOT NULL CHECK (match_method = ANY (ARRAY['exact_email'::text, 'exact_phone'::text, 'reference_number'::text, 'manual_review'::text, 'unmatched_preserved'::text])),
  matched_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT integration_ft_id_map_pkey PRIMARY KEY (id),
  CONSTRAINT integration_ft_id_map_matched_by_fkey FOREIGN KEY (matched_by) REFERENCES public.profiles(id)
);
CREATE TABLE public.finance_migration_batches (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  label text NOT NULL,
  started_at timestamp with time zone NOT NULL DEFAULT now(),
  completed_at timestamp with time zone,
  status text NOT NULL DEFAULT 'in_progress'::text CHECK (status = ANY (ARRAY['in_progress'::text, 'completed'::text, 'failed'::text, 'rolled_back'::text])),
  notes text,
  CONSTRAINT finance_migration_batches_pkey PRIMARY KEY (id)
);
CREATE TABLE public.finance_migration_exceptions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  batch_id uuid,
  source_table text NOT NULL,
  legacy_id uuid,
  reason text NOT NULL,
  raw jsonb,
  resolved boolean NOT NULL DEFAULT false,
  resolved_by uuid,
  resolved_at timestamp with time zone,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT finance_migration_exceptions_pkey PRIMARY KEY (id),
  CONSTRAINT finance_migration_exceptions_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES public.finance_migration_batches(id),
  CONSTRAINT finance_migration_exceptions_resolved_by_fkey FOREIGN KEY (resolved_by) REFERENCES public.profiles(id)
);
CREATE TABLE public.finance_legacy_participants (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  type text NOT NULL CHECK (type = ANY (ARRAY['internship'::text, 'holiday_class'::text, 'bootcamp'::text, 'course'::text])),
  full_name text NOT NULL,
  email text,
  phone text,
  school text,
  department text,
  program text,
  id_card_number text,
  guardian_name text,
  guardian_phone text,
  referral_source text,
  referral_person_name text,
  referral_fee_due numeric NOT NULL DEFAULT 0,
  referral_fee_paid boolean NOT NULL DEFAULT false,
  referral_fee_payment_date date,
  start_date date,
  duration text,
  expiry_date date,
  status text NOT NULL DEFAULT 'enrolled'::text CHECK (status = ANY (ARRAY['enrolled'::text, 'in_progress'::text, 'completed'::text, 'certificate_issued'::text, 'dropped'::text, 'suspended'::text])),
  waitlist boolean NOT NULL DEFAULT false,
  notes text,
  created_by uuid,
  legacy_id uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT finance_legacy_participants_pkey PRIMARY KEY (id),
  CONSTRAINT finance_legacy_participants_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id)
);
CREATE TABLE public.storage_objects (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  bucket_name text NOT NULL,
  object_path text NOT NULL UNIQUE,
  original_filename text NOT NULL,
  mime_type text NOT NULL,
  size_bytes bigint NOT NULL CHECK (size_bytes > 0),
  checksum text,
  owner_profile_id uuid,
  classification text NOT NULL DEFAULT 'confidential'::text CHECK (classification = ANY (ARRAY['public'::text, 'internal'::text, 'confidential'::text, 'highly_confidential'::text])),
  uploaded_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  deleted_at timestamp with time zone,
  CONSTRAINT storage_objects_pkey PRIMARY KEY (id),
  CONSTRAINT storage_objects_owner_profile_id_fkey FOREIGN KEY (owner_profile_id) REFERENCES public.profiles(id),
  CONSTRAINT storage_objects_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES public.profiles(id)
);
CREATE TABLE public.attendance_sessions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  offering_id uuid,
  cohort_id uuid NOT NULL,
  title text NOT NULL,
  session_type text NOT NULL DEFAULT 'class'::text CHECK (session_type = ANY (ARRAY['class'::text, 'workshop'::text, 'check_in'::text, 'project'::text, 'event'::text])),
  starts_at timestamp with time zone NOT NULL,
  ends_at timestamp with time zone,
  location_text text,
  status USER-DEFINED NOT NULL DEFAULT 'draft'::attendance_session_status,
  method text NOT NULL DEFAULT 'manual'::text,
  created_by uuid,
  closed_at timestamp with time zone,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT attendance_sessions_pkey PRIMARY KEY (id),
  CONSTRAINT attendance_sessions_offering_id_fkey FOREIGN KEY (offering_id) REFERENCES public.offerings(id),
  CONSTRAINT attendance_sessions_cohort_id_fkey FOREIGN KEY (cohort_id) REFERENCES public.cohorts(id),
  CONSTRAINT attendance_sessions_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id)
);
CREATE TABLE public.attendance_records (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  attendance_session_id uuid NOT NULL,
  enrolment_id uuid NOT NULL,
  status USER-DEFINED NOT NULL DEFAULT 'not_recorded'::attendance_status,
  recorded_by uuid,
  recorded_at timestamp with time zone NOT NULL DEFAULT now(),
  note text,
  corrected_at timestamp with time zone,
  corrected_by uuid,
  correction_reason text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT attendance_records_pkey PRIMARY KEY (id),
  CONSTRAINT attendance_records_attendance_session_id_fkey FOREIGN KEY (attendance_session_id) REFERENCES public.attendance_sessions(id),
  CONSTRAINT attendance_records_enrolment_id_fkey FOREIGN KEY (enrolment_id) REFERENCES public.enrolments(id),
  CONSTRAINT attendance_records_recorded_by_fkey FOREIGN KEY (recorded_by) REFERENCES public.profiles(id),
  CONSTRAINT attendance_records_corrected_by_fkey FOREIGN KEY (corrected_by) REFERENCES public.profiles(id)
);
CREATE TABLE public.announcements (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  title text NOT NULL,
  body text NOT NULL,
  audience_type text NOT NULL DEFAULT 'organisation'::text CHECK (audience_type = ANY (ARRAY['organisation'::text, 'offering'::text, 'cohort'::text, 'selected_users'::text])),
  audience_id uuid,
  publication_status USER-DEFINED NOT NULL DEFAULT 'draft'::publication_status,
  publish_at timestamp with time zone,
  expires_at timestamp with time zone,
  created_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT announcements_pkey PRIMARY KEY (id),
  CONSTRAINT announcements_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id)
);
CREATE TABLE public.notifications (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  recipient_id uuid NOT NULL,
  type text NOT NULL,
  title text NOT NULL,
  body text NOT NULL,
  related_entity_type text,
  related_entity_id uuid,
  channel text NOT NULL DEFAULT 'in_app'::text CHECK (channel = ANY (ARRAY['in_app'::text, 'email'::text, 'push'::text])),
  status USER-DEFINED NOT NULL DEFAULT 'queued'::notification_status,
  scheduled_at timestamp with time zone,
  sent_at timestamp with time zone,
  delivered_at timestamp with time zone,
  read_at timestamp with time zone,
  provider_message_id text,
  failure_code text,
  retry_count integer NOT NULL DEFAULT 0,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT notifications_pkey PRIMARY KEY (id),
  CONSTRAINT notifications_recipient_id_fkey FOREIGN KEY (recipient_id) REFERENCES public.profiles(id)
);
CREATE TABLE public.digital_resources (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  title text NOT NULL,
  description text,
  storage_object_id uuid,
  external_url text,
  visibility_scope_type USER-DEFINED NOT NULL DEFAULT 'organisation'::scope_type,
  visibility_scope_id uuid,
  version integer NOT NULL DEFAULT 1,
  created_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT digital_resources_pkey PRIMARY KEY (id),
  CONSTRAINT digital_resources_storage_object_id_fkey FOREIGN KEY (storage_object_id) REFERENCES public.storage_objects(id),
  CONSTRAINT digital_resources_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id)
);
CREATE TABLE public.task_resources (
  task_id uuid NOT NULL,
  resource_id uuid NOT NULL,
  sort_order integer NOT NULL DEFAULT 0,
  CONSTRAINT task_resources_pkey PRIMARY KEY (task_id, resource_id),
  CONSTRAINT task_resources_task_id_fkey FOREIGN KEY (task_id) REFERENCES public.tasks(id),
  CONSTRAINT task_resources_resource_id_fkey FOREIGN KEY (resource_id) REFERENCES public.digital_resources(id)
);
CREATE TABLE public.submission_files (
  submission_id uuid NOT NULL,
  storage_object_id uuid NOT NULL,
  sort_order integer NOT NULL DEFAULT 0,
  CONSTRAINT submission_files_pkey PRIMARY KEY (submission_id, storage_object_id),
  CONSTRAINT submission_files_submission_id_fkey FOREIGN KEY (submission_id) REFERENCES public.submissions(id),
  CONSTRAINT submission_files_storage_object_id_fkey FOREIGN KEY (storage_object_id) REFERENCES public.storage_objects(id)
);
CREATE TABLE public.policy_documents (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  policy_key text NOT NULL,
  version text NOT NULL,
  title text NOT NULL,
  content_url text NOT NULL,
  effective_at timestamp with time zone NOT NULL,
  is_required boolean NOT NULL DEFAULT true,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT policy_documents_pkey PRIMARY KEY (id)
);
CREATE TABLE public.policy_acceptances (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  profile_id uuid NOT NULL,
  policy_document_id uuid NOT NULL,
  accepted_at timestamp with time zone NOT NULL DEFAULT now(),
  source_application text NOT NULL DEFAULT 'hub'::text CHECK (source_application = ANY (ARRAY['website'::text, 'admin'::text, 'hub'::text])),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT policy_acceptances_pkey PRIMARY KEY (id),
  CONSTRAINT policy_acceptances_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES public.profiles(id),
  CONSTRAINT policy_acceptances_policy_document_id_fkey FOREIGN KEY (policy_document_id) REFERENCES public.policy_documents(id)
);
CREATE TABLE public.finance_legacy_audit_event_map (
  legacy_audit_id uuid NOT NULL,
  target_event_id uuid NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT finance_legacy_audit_event_map_pkey PRIMARY KEY (legacy_audit_id),
  CONSTRAINT finance_legacy_audit_event_map_target_event_id_fkey FOREIGN KEY (target_event_id) REFERENCES public.finance_transaction_events(id)
);

CREATE TABLE public.absence_requests (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  requester_id uuid NOT NULL,
  enrolment_id uuid,
  type text NOT NULL CHECK (type = ANY (ARRAY['sick'::text, 'personal'::text, 'school_exam'::text, 'annual'::text])),
  start_date date NOT NULL,
  end_date date NOT NULL,
  reason text,
  status text NOT NULL DEFAULT 'pending'::text CHECK (status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text])),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT absence_requests_pkey PRIMARY KEY (id),
  CONSTRAINT absence_requests_date_order CHECK (end_date >= start_date),
  CONSTRAINT absence_requests_requester_id_fkey FOREIGN KEY (requester_id) REFERENCES public.profiles(id) ON DELETE CASCADE,
  CONSTRAINT absence_requests_enrolment_id_fkey FOREIGN KEY (enrolment_id) REFERENCES public.enrolments(id) ON DELETE SET NULL
);
CREATE TABLE public.absence_request_approvals (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL,
  approver_id uuid NOT NULL,
  decision text CHECK (decision = ANY (ARRAY['approved'::text, 'rejected'::text])),
  decided_at timestamp with time zone,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT absence_request_approvals_pkey PRIMARY KEY (id),
  CONSTRAINT absence_request_approvals_unique_approver UNIQUE (request_id, approver_id),
  CONSTRAINT absence_request_approvals_request_id_fkey FOREIGN KEY (request_id) REFERENCES public.absence_requests(id) ON DELETE CASCADE,
  CONSTRAINT absence_request_approvals_approver_id_fkey FOREIGN KEY (approver_id) REFERENCES public.profiles(id) ON DELETE CASCADE
);
CREATE TABLE public.issue_reports (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  reporter_id uuid NOT NULL,
  category text NOT NULL CHECK (category = ANY (ARRAY['facility'::text, 'asset'::text, 'curriculum'::text, 'safety_conduct'::text, 'other'::text])),
  description text NOT NULL,
  status text NOT NULL DEFAULT 'open'::text CHECK (status = ANY (ARRAY['open'::text, 'in_progress'::text, 'resolved'::text])),
  asset_id uuid,
  offering_id uuid,
  resolved_by uuid,
  resolved_at timestamp with time zone,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT issue_reports_pkey PRIMARY KEY (id),
  CONSTRAINT issue_reports_reporter_id_fkey FOREIGN KEY (reporter_id) REFERENCES public.profiles(id) ON DELETE CASCADE,
  CONSTRAINT issue_reports_offering_id_fkey FOREIGN KEY (offering_id) REFERENCES public.offerings(id) ON DELETE SET NULL,
  CONSTRAINT issue_reports_resolved_by_fkey FOREIGN KEY (resolved_by) REFERENCES public.profiles(id) ON DELETE SET NULL
);
CREATE TABLE public.assets (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  name text NOT NULL,
  type text NOT NULL CHECK (type = ANY (ARRAY['physical'::text, 'digital'::text])),
  status text NOT NULL DEFAULT 'fine'::text CHECK (status = ANY (ARRAY['fine'::text, 'needs_repair'::text, 'retired'::text])),
  assigned_to uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  deleted_at timestamp with time zone,
  CONSTRAINT assets_pkey PRIMARY KEY (id),
  CONSTRAINT assets_assigned_to_fkey FOREIGN KEY (assigned_to) REFERENCES public.profiles(id) ON DELETE SET NULL
);
