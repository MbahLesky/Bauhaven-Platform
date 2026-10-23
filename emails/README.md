# Bauhaven Email Templates

This directory contains the production-ready, fully responsive HTML email templates for Bauhaven. All templates follow the official **Bauhaven Brand Guidelines** (`Bauhaven-Brand-Guidelines.md`) with 100% inline CSS, high-contrast typography (Montserrat headings, Archivo body), mobile compatibility (Outlook, Gmail, Apple Mail), and the signature multi-color gradient header strip.

---

## Brand Palette Reference

| Element / Color | Hex Code | Usage |
|---|---|---|
| **Signature Red** | `#D72638` | Primary CTA buttons, key alerts, gradient stop 0% |
| **Deep Orange** | `#F26B3B` | Gradient stop 25%, pending status indicators |
| **Gold** | `#FED500` | Gradient stop 50% |
| **Mint Green** | `#54BE8D` | Gradient stop 75%, approval badges, success states |
| **Cyan Blue** | `#26AAD1` | Gradient stop 100%, secondary links, task badges |
| **Dark Neutral** | `#1E1E1E` | Headings, primary text |
| **Subdued Text** | `#666666` / `#777777` | Captions, labels, fallback links |
| **Surface Background** | `#F8F8F8` | Outer email background |
| **Card Container** | `#FFFFFF` | Centered 580px container with `#EAEAEA` border |

---

## Directory Structure & Complete Template Index

```text
emails/
├── README.md                              # This documentation and setup guide
│
├── supabase-auth/                         # Supabase Auth Dashboard (Go Templates)
│   ├── confirm-signup.html                # 1. Confirm Sign Up (Link + OTP)
│   ├── invite-user.html                   # 2. Invite User (Staff/Admin/Student)
│   ├── magic-link.html                    # 3. Magic Link or OTP Sign-In
│   ├── change-email.html                  # 4. Change Email Address
│   └── reset-password.html                # 5. Reset Password
│
└── transactional/                         # Transactional (Resend / Edge Functions / API)
    ├── new-application.html               # 6a. New Application (Applicant Receipt)
    ├── new-application-staff-alert.html   # 6b. New Application (Staff Alert: To team, BCC bauhaventc)
    ├── application-approved.html          # Admissions Acceptance Notification
    ├── task-assigned.html                 # Academy Task Assignment Notification
    ├── task-reminder.html                 # 7. Task Reminder (Deadline Approaching)
    ├── permission-request.html            # 8. Permission Request (Access Elevation Review)
    └── just-an-update.html                # 9. Just an Update (Announcements / News / Broadcasts)
```

---

## 1. Supabase Auth Email Templates (Dashboard Configuration)

Paste these templates directly into your **Supabase Dashboard**:  
👉 **Project Dashboard &rarr; Authentication &rarr; Email Templates**

Sender address for Supabase Auth in dashboard settings: `team@bauhaven.com` (or `team@gmail.com`).

### 1.1 Confirm Sign Up (`emails/supabase-auth/confirm-signup.html`)
- **Dashboard Section**: *Confirm signup*
- **Subject Line**: `Confirm your Bauhaven account`
- **Variables**: `{{ .ConfirmationURL }}`, `{{ .Token }}`, `{{ .Email }}`

### 1.2 Invite User (`emails/supabase-auth/invite-user.html`)
- **Dashboard Section**: *Invite user*
- **Subject Line**: `You've been invited to Bauhaven`
- **Variables**: `{{ .ConfirmationURL }}`, `{{ .Token }}`, `{{ .Email }}`

### 1.3 Magic Link or OTP (`emails/supabase-auth/magic-link.html`)
- **Dashboard Section**: *Magic Link*
- **Subject Line**: `Your Bauhaven login link and code`
- **Variables**: `{{ .ConfirmationURL }}`, `{{ .Token }}`, `{{ .Email }}`

### 1.4 Change Email Address (`emails/supabase-auth/change-email.html`)
- **Dashboard Section**: *Change Email Address*
- **Subject Line**: `Confirm your new email address for Bauhaven`
- **Variables**: `{{ .ConfirmationURL }}`, `{{ .Token }}`, `{{ .Email }}`, `{{ .NewEmail }}`

### 1.5 Reset Password (`emails/supabase-auth/reset-password.html`)
- **Dashboard Section**: *Reset Password*
- **Subject Line**: `Reset your Bauhaven password`
- **Variables**: `{{ .ConfirmationURL }}`, `{{ .Token }}`

---

## 2. Transactional Email Templates (Resend / Edge Functions)

Transactional emails are dispatched via [Resend](https://resend.com) from Supabase Edge Functions or the website backend.

### 2.1 New Application (Applicant Receipt & Staff Alert)
- **Applicant Receipt Template**: `emails/transactional/new-application.html`
  - **Subject**: `Application Received: {{program}} - Bauhaven`
  - **Recipient**: Applicant email address
- **Staff Alert Template**: `emails/transactional/new-application-staff-alert.html`
  - **Subject**: `New Application: {{applicant_name}} - {{program}}`
  - **To**: `team@bauhaven.com`
  - **BCC**: `bauhaventc@gmail.com`
  - **From**: `Bauhaven Applications <team@bauhaven.com>`
  - **Variables**: `{{applicant_name}}`, `{{applicant_email}}`, `{{applicant_phone}}`, `{{program}}`, `{{course}}`, `{{level}}`, `{{start_date}}`, `{{duration}}`, `{{message}}`, `{{admin_review_url}}`

### 2.2 Task Reminder (`emails/transactional/task-reminder.html`)
- **Subject**: `Reminder: Task due soon - {{task_title}}`
- **Sender**: `Bauhaven Tasks <team@bauhaven.com>`
- **Variables**: `{{name}}`, `{{task_title}}`, `{{due_date}}`, `{{time_remaining}}`, `{{instructions}}`, `{{portal_url}}`

### 2.3 Permission Request (`emails/transactional/permission-request.html`)
- **Subject**: `Permission Request: {{requested_permission}} from {{requester_name}}`
- **Sender**: `Bauhaven Requests <team@bauhaven.com>`
- **Variables**: `{{requester_name}}`, `{{requester_email}}`, `{{requested_permission}}`, `{{scope}}`, `{{reason}}`, `{{submitted_at}}`, `{{admin_url}}`

### 2.4 Just an Update (`emails/transactional/just-an-update.html`)
- **Subject**: `{{update_title}} - Bauhaven Update`
- **Sender**: `Bauhaven Team <team@bauhaven.com>`
- **Variables**: `{{name}}`, `{{update_title}}`, `{{update_body}}`, `{{highlights}}`, `{{cta_label}}`, `{{cta_url}}`

---

## 3. Sender Header & Key Mapping

| Purpose | Default Sender | Resend Key Variable |
|---|---|---|
| **Admissions & Applications** | `Bauhaven Applications <team@bauhaven.com>` | `resend_api_key (applications)` |
| **Tasks & Reminders** | `Bauhaven Tasks <team@bauhaven.com>` | `resend_api_key (notify_tasks)` |
| **Requests & Permissions** | `Bauhaven Requests <team@bauhaven.com>` | `resend_api_key (request/permissions)` |
| **Info & Platform Updates** | `Bauhaven Team <team@bauhaven.com>` | `resend_api_key (info and updates)` |
| **Supabase Auth** | `Bauhaven <team@bauhaven.com>` | Supabase Dashboard SMTP / Custom Sender |
