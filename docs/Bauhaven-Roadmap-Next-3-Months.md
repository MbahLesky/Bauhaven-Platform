# Bauhaven Platform — 3-Month Strategic Roadmap & Architecture Specification

| Field | Value |
|---|---|
| Document Code | `BAU-ROADMAP-2026-Q4` |
| Version | 1.0 |
| Date | 29 October 2026 |
| Target Repositories | `Bauhaven-Platform`, `Bauhaven-Admin-Web`, `Bauhaven-Academy-Web`, `bauhaven-admin`, `bauhaven-hub2`, `bauhaven-website` |
| Status | Canonical Multi-Domain & LMS Implementation Plan |

---

## 1. Executive Vision: The De-Monolithization Strategy

The current public web presence is being restructured from a single complex website into a clean, purpose-driven ecosystem of dedicated subdomains. Each subsite serves a specific audience with tailored user journeys, while sharing a unified identity, database, and backend infrastructure:

```text
                                  ┌──────────────────────────────┐
                                  │      bauhaven.com (Gateway)  │
                                  │   Brand, Story, Ecosystem    │
                                  └──────────────┬───────────────┘
                     ┌───────────────────────────┼───────────────────────────┐
                     ▼                           ▼                           ▼
       ┌───────────────────────────┐ ┌───────────────────────────┐ ┌───────────────────────────┐
       │   services.bauhaven.com   │ │    academy.bauhaven.com   │ │     blog.bauhaven.com     │
       │   Digital Agency Services │ │   All Educational Courses │ │   Articles, Tech Guides,  │
       │   & Client Portfolios     │ │   Bootcamps & Cohorts     │ │   Student Spotlight Stories│
       └───────────────────────────┘ └─────────────┬─────────────┘ └───────────────────────────┘
                                                   │ Pay & Instant Enroll
                                                   ▼
                                     ┌───────────────────────────┐
                                     │     hub.bauhaven.com      │
                                     │  Interactive Online LMS,  │
                                     │  30-Day Courses & Tasks   │
                                     └─────────────┬─────────────┘
                                                   │ Administrative Control
                                                   ▼
                                     ┌───────────────────────────┐
                                     │     admin.bauhaven.com    │
                                     │  Operations, JSON Course  │
                                     │  Manager, Attendance & Fin│
                                     └───────────────────────────┘
```

---

## 2. Subdomain Breakdown & Specifications

### 2.1 Main Brand Gateway (`bauhaven.com`)
*Target Audience: General visitors, partners, prospective clients, and students looking for orientation.*

**Structure:** A fast, sleek, single-page narrative that tells Bauhaven's story in under 60 seconds:
1. **Hero:** Clear brand statement: *"Transforming Ideas into Digital Products & Training Africa's Next-Generation Tech Leaders."* Direct CTAs: `[Explore Services]` and `[Browse Academy]`.
2. **About Us:** Bauhaven's mission, culture, and physical community hub in Cameroon.
3. **Agency Services Teaser:** 4 highlight cards (UI/UX, Web/Mobile Apps, Branding, Digital Marketing) with direct links to `services.bauhaven.com`.
4. **Academy Programs Teaser:** Upcoming cohorts, 30-day online courses, and holiday bootcamps with direct links to `academy.bauhaven.com`.
5. **Impact Metrics:** Counters for students trained (500+), commercial projects delivered (40+), and client satisfaction rate.
6. **Live Testimonial Wall:** Dynamic testimonials queried directly from verified database records.
7. **Meet the Leadership & Mentors:** Team member profiles, credentials, and expertise.
8. **"Bawe" AI Ecosystem Assistant:** A lightweight floating assistant in the bottom corner powered by Gemini API, answering questions about locations, programs, and inquiries in English and French.
9. **Footer:** Cross-subdomain navigation, social links, legal terms, and accreditation.

### 2.2 Digital Agency Subsite (`services.bauhaven.com` / `studio.bauhaven.com`)
*Target Audience: Businesses, corporate clients, startups, and organizations seeking commercial digital solutions.*

**Key Offerings:**
- **Brand & Visual Identity:** Logo suites, design systems, brand guidelines.
- **UI & UX Product Design:** User research, wireframing, high-fidelity prototypes in Figma.
- **Web & Mobile Development:** Custom web applications, mobile apps (Flutter, iOS, Android), enterprise portals.
- **Digital Growth & Marketing:** SEO, content strategy, social media campaigns.
- **Interactive Quote / Inquiry Form:** Step-by-step project intake form sending instant notifications to admin staff with automated lead creation in Supabase.
- **Client Case Studies:** Deep dives into delivered projects with screenshots, metrics, and client quotes.

### 2.3 Academy & Training Subsite (`academy.bauhaven.com`)
*Target Audience: Aspiring learners, students, career switchers, and parents seeking youth holiday tech programs.*

> **Architectural Decision: Unified Training Domain**  
> Rather than fragmenting into multiple domains (`programs.bauhaven.com` or `events.bauhaven.com`), all educational offerings live under `academy.bauhaven.com` to consolidate SEO authority, simplify checkout, and allow students to explore all learning pathways in one catalog.

**Category Filters on Catalog:**
1. **Online Self-Paced Courses:** 30-day structured online programs (e.g., Graphic Design Beginners, Web Fundamentals).
2. **Intensive Cohorts & Internships:** 3–6 month hybrid/in-person training with assigned mentors and live projects.
3. **Seasonal Youth Bootcamps:** Easter, Summer, and Holiday tech workshops with guardian enrollment options.

**Course Detail Page:**
- Detailed syllabus overview, prerequisites, instructor bios, weekly breakdown, and certification preview.
- **Direct Checkout Button:** `[Enroll Now — 20,000 XAF]` with integrated MTN Mobile Money, Orange Money, and Card payment.

### 2.4 Knowledge & Blog Subsite (`blog.bauhaven.com`)
*Target Audience: Tech community, students, and SEO acquisition.*
- High-quality tutorials, student project retrospectives, tech industry insights, and event recaps.
- Managed and approved through the Admin Content Editor.

---

## 3. Hybrid JSON Course & Curriculum Engine

### 3.1 The Problem
Building a 30-day course with 30 modules, lesson summaries, code snippets, and quizzes through traditional 50-field admin web forms is tedious, error-prone, and slow.

### 3.2 The Hybrid Architecture
```text
┌─────────────────────────┐          ┌──────────────────────────┐          ┌─────────────────────────┐
│   Admin / Curriculum    │          │    Admin Web Portal      │          │   PostgreSQL Database   │
│   Designer (Offline)    │          │   Validation Engine      │          │     (Supabase)          │
└────────────┬────────────┘          └────────────┬─────────────┘          └────────────┬────────────┘
             │                                    │                                     │
             │ 1. Download JSON Template          │                                     │
             │◄───────────────────────────────────┤                                     │
             │                                    │                                     │
             │ 2. Edit JSON in VS Code / Editor   │                                     │
             │    (or generate with LLM)          │                                     │
             │                                    │                                     │
             │ 3. Upload course-curriculum.json   │                                     │
             ├───────────────────────────────────►│                                     │
             │                                    │ 4. Validate Schema & Structure      │
             │                                    │    (Reports line & syntax errors)   │
             │                                    │                                     │
             │                                    │ 5. Store validated JSONB            │
             │                                    ├────────────────────────────────────►│
             │                                    │                                     │ programs.curriculum_data
             │ 6. Instant Accordion Preview       │                                     │ (JSONB)
             │◄───────────────────────────────────┤                                     │
```

### 3.3 Course JSON Schema Specification (`course-schema.json`)
```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "course_id": "bh-gd-30",
  "title": "Graphic Design for Beginners (30-Day Masterclass)",
  "duration_days": 30,
  "level": "beginner",
  "category": "design",
  "modules": [
    {
      "day": 1,
      "title": "Introduction to Visual Hierarchy & Canvas Setup",
      "summary": "Understand whitespace, balance, and setting up your first Figma workspace.",
      "reading_markdown": "# Day 1: Welcome to Graphic Design...\n\nEvery great design starts with...",
      "video_url": "https://vimeo.com/123456789",
      "exercise": {
        "title": "Create a Balanced Social Media Banner",
        "description": "Using Figma, design a 1080x1080 banner using only 2 colors and 1 typeface.",
        "starter_assets_url": "https://storage.bauhaven.com/courses/gd30/day1-assets.zip"
      },
      "quiz": [
        {
          "question": "What is the primary purpose of visual hierarchy?",
          "options": [
            "To make designs look colorful",
            "To guide the viewer's eye to the most important element first",
            "To fill up all empty spaces",
            "To choose fonts randomly"
          ],
          "correct_option_index": 1,
          "explanation": "Visual hierarchy organizes elements in order of significance so readers know where to look first."
        }
      ]
    }
  ]
}
```

---

## 4. Hub LMS: Online Interactive Learning Experience

When an enrolled learner logs into `hub.bauhaven.com`:

### 4.1 Daily Learning Dashboard
- **Day-by-Day Timeline:** Visual roadmap (e.g. Day 1 through Day 30) with completed checkmarks, current active day, and locked future days (or open self-paced access).
- **Lesson Player:**
  - Rich reading section with code and image blocks.
  - Responsive video embed.
  - Interactive knowledge checkpoint quiz (instant feedback on submission).
  - Practical task dropzone (submit link to Figma, GitHub, or file upload).
- **Gamified Daily Streak:** 🔥 **Streak Counter** tracking consecutive days learned to boost completion rates.

### 4.2 Data Models for Learning Progress
```sql
-- Lesson completion per student
create table public.learner_lesson_progress (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  program_id uuid not null references public.offerings(id) on delete cascade,
  enrolment_id uuid not null references public.enrolments(id) on delete cascade,
  day_number int not null,
  is_completed boolean not null default false,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint uq_learner_lesson unique (enrolment_id, day_number)
);

-- Quiz attempt records
create table public.learner_quiz_attempts (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  enrolment_id uuid not null references public.enrolments(id) on delete cascade,
  day_number int not null,
  score_percent numeric(5,2) not null,
  passed boolean not null default false,
  answers jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
```

---

## 5. Instant Payment-to-Enrollment Pipeline

```text
Visitor on academy.bauhaven.com
  │
  ├─ Selects Course (e.g. Graphic Design 30-Day — 20,000 XAF)
  ├─ Enters Name, Email, Phone
  ├─ Selects MTN Mobile Money / Orange Money / Card
  │
  ▼ [Regional Payment Gateway API (Notch Pay / Flutterwave)]
Payer confirms USSD prompt on their mobile phone (MoMo PIN)
  │
  ▼ [Webhook received by Supabase Edge Function]
1. Verify cryptographic webhook signature.
2. Insert approved finance_income record with auto_approved status.
3. Automatically provision auth account & profile if not already registered.
4. Insert active enrolment record pointing to the program.
5. Send welcome email + WhatsApp notification with 1-click magic link to hub.bauhaven.com.
  │
  ▼
Learner opens hub.bauhaven.com -> Course is instantly unlocked with Day 1 active!
```

---

## 6. Strategic High-Value Suggestions for the Next Version

Beyond the core subdomains and LMS engine, these 6 strategic enhancements are recommended:

### 1. WhatsApp & SMS Automated Alerts (High Regional Open Rates)
- In Cameroon and Central Africa, email open rates are often below 25%, whereas WhatsApp is near 98%.
- Integrate a WhatsApp Business API / SMS gateway (e.g. Twilio or Termii):
  - Send instant WhatsApp payment confirmation & Hub access link.
  - Send attendance absence notifications to students (and parents for youth holiday camps).
  - Send tuition coverage expiration alerts (3 days prior & on expiration).

### 2. "Bawe" AI In-Lesson Tutor (24/7 Learning Companion)
- Beyond the landing page sales assistant, embed "Bawe" directly inside the Hub lesson reader:
- When a student is reading Day 8 on CSS Flexbox or Photoshop Pen tool and gets confused, they can click `"Ask Bawe"`:
  - *"Explain how align-items differs from justify-content with an analogy"*
  - *"Why is my Figma frame clipping my drop shadow?"*
- Keeps students unblocked 24/7 without waiting for instructor office hours.

### 3. In-Browser "Try It Yourself" Sandboxes (W3Schools Style)
- For web development courses: an embedded lightweight sandbox (Monaco / CodeMirror) where students type HTML/CSS and see live output right in the browser.
- Eliminates local installation barriers for beginners on Day 1.

### 4. Verified Graduate Talent Profiles (`bauhaven.com/u/[u_code]`)
- Every graduate receives a public portfolio link based on their unique `u_code` (e.g., `bauhaven.com/u/BH-26-1001`).
- Displays their verified certificates, completed courses, and best project submissions.
- Employers browsing `services.bauhaven.com` can hire Bauhaven alumni directly!

### 5. Guardian Contact Tracking for Youth Holiday Camps
- Add an explicit `guardian_name`, `guardian_phone`, `guardian_email` block on holiday bootcamp enrollments.
- Parents receive daily check-in alerts and invites to the demo-day final presentation.

### 6. Duolingo-Style Gamification & Streaks
- Daily streak flame (`🔥 7-Day Streak`).
- Completing a 30-day course without breaking the streak earns a **Bauhaven Honor Roll Badge** and a 10% voucher for their next cohort or internship.

---

## 7. 3-Month Implementation Schedule

| Month | Focus Area | Deliverables & Milestones |
|---|---|---|
| **Month 1** | **Subdomain Setup & JSON Course Engine** | • Deploy `bauhaven.com` (Gateway) and `services.bauhaven.com`<br>• Implement Admin JSON course download/upload validator<br>• Setup course schema and database `jsonb` storage<br>• Prototype "Bawe" Gateway bot |
| **Month 2** | **Hub LMS & Payment Gateway Integration** | • Build Day-by-Day course reader on `hub.bauhaven.com`<br>• Integrate MTN/Orange MoMo & Card payment gateway on `academy.bauhaven.com`<br>• Automated webhook provisioning and instant enrollment pipeline<br>• Student lesson progress & quiz grading schema |
| **Month 3** | **Interactive Tools, Certificates & Polish** | • In-lesson "Bawe" AI Tutor integration<br>• Automated digital certificate generation & verification (`/verify/[cert_code]`)<br>• WhatsApp notification pipeline for payments & attendance<br>• Daily streak gamification on Hub |
