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

## Directory Structure

```text
emails/
├── README.md                          # This documentation and setup guide
├── supabase-auth/                     # Templates for Supabase Auth Dashboard
│   ├── confirm-signup.html            # New user signup verification
│   ├── invite-user.html               # Staff, admin, and student invitations
│   ├── magic-link.html                # Passwordless one-time login
│   ├── reset-password.html            # Password recovery
│   └── change-email.html              # Email change confirmation
└── transactional/                     # Templates for Resend & Edge Functions
    ├── application-approved.html      # Admissions acceptance notification
    ├── application-received.html      # Admissions submission acknowledgement
    └── task-assigned.html             # Academy task assignment notification
```

---

## 1. Supabase Auth Email Templates

Paste these templates directly into the **Supabase Dashboard**:  
👉 **Project Dashboard &rarr; Authentication &rarr; Email Templates**

These templates use Supabase's native **Go template** tags (`{{ .ConfirmationURL }}`, `{{ .Token }}`, etc.) and require no external email service configuration.

### 1.1 Confirm Signup (`emails/supabase-auth/confirm-signup.html`)
- **Dashboard Section**: *Confirm signup*
- **Subject Line**: `Confirm your Bauhaven account`
- **Purpose**: Sent when a new user signs up on the website, academy, or mobile app.
- **Variables**:
  - `{{ .ConfirmationURL }}`: Verification link.
  - `{{ .Token }}`: 6-digit confirmation code.
  - `{{ .Email }}`: User's email address.

### 1.2 Invite User (`emails/supabase-auth/invite-user.html`)
- **Dashboard Section**: *Invite user*
- **Subject Line**: `You've been invited to Bauhaven`
- **Purpose**: Sent by `admin.auth.admin.inviteUserByEmail()` when inviting new administrators, staff, mentors, or accepted students.
- **Variables**:
  - `{{ .ConfirmationURL }}`: Invitation acceptance link.
  - `{{ .Token }}`: Direct invite token.
  - `{{ .Email }}`: Invitee's email address.

### 1.3 Magic Link (`emails/supabase-auth/magic-link.html`)
- **Dashboard Section**: *Magic Link*
- **Subject Line**: `Your Bauhaven login link`
- **Purpose**: Sent when a user requests passwordless authentication.
- **Variables**:
  - `{{ .ConfirmationURL }}`: One-time login URL.
  - `{{ .Token }}`: One-time OTP.

### 1.4 Reset Password (`emails/supabase-auth/reset-password.html`)
- **Dashboard Section**: *Reset Password*
- **Subject Line**: `Reset your Bauhaven password`
- **Purpose**: Sent when a user initiates a password recovery request.
- **Variables**:
  - `{{ .ConfirmationURL }}`: Password reset link.
  - `{{ .Token }}`: Security token code.

### 1.5 Change Email Address (`emails/supabase-auth/change-email.html`)
- **Dashboard Section**: *Change Email Address*
- **Subject Line**: `Confirm your new email address for Bauhaven`
- **Purpose**: Sent when a user changes their primary email address.
- **Variables**:
  - `{{ .ConfirmationURL }}`: Confirmation link.
  - `{{ .Token }}`: Verification code.
  - `{{ .Email }}`: Current email.
  - `{{ .NewEmail }}`: Target new email.

---

## 2. Transactional Email Templates (Resend / Edge Functions)

These templates are used for event-driven transactional notifications sent via [Resend](https://resend.com) from Supabase Edge Functions or backend services.

### 2.1 Application Approved (`emails/transactional/application-approved.html`)
- **Default Sender**: `Bauhaven Admissions <admissions@bauhaven.com>`
- **Subject Line**: `Congratulations! Your Bauhaven application has been approved`
- **Edge Function**: `supabase/functions/approve-application`
- **Template Variables**:
  - `{{name}}`: Applicant's full name.
  - `{{offering_title}}`: Name of the programme (e.g. *Full-Stack Software Engineering*).
  - `{{cohort_name}}`: Cohort identifier (e.g. *Cohort Alpha 2026*).
  - `{{start_date}}`: Programme start date.
  - `{{portal_url}}`: Link to the Academy portal (`https://academy.bauhaven.com` or `http://localhost:3002`).

### 2.2 Task Assigned (`emails/transactional/task-assigned.html`)
- **Default Sender**: `Bauhaven Tasks <info@bauhaven.com>`
- **Subject Line**: `New task assigned: {{task_title}}`
- **Edge Function**: `supabase/functions/notify-task-assignment`
- **Template Variables**:
  - `{{name}}`: Student's name.
  - `{{task_title}}`: Name of the assignment.
  - `{{due_date}}`: Formatted deadline (e.g. *15 November 2026*).
  - `{{instructions}}`: Brief excerpt or summary of task instructions.
  - `{{portal_url}}`: Direct link to task in Academy portal.

### 2.3 Application Received (`emails/transactional/application-received.html`)
- **Default Sender**: `Bauhaven Admissions <admissions@bauhaven.com>`
- **Subject Line**: `We've received your Bauhaven application`
- **Usage**: Website application form submission trigger.
- **Template Variables**:
  - `{{name}}`: Applicant's name.
  - `{{offering_title}}`: Target programme.
  - `{{application_id}}`: Tracking reference code.

---

## 3. Resend Sender Configuration

When sending transactional emails, ensure the `from` field matches the registered domain in Resend:

| Channel / Type | From Header | Resend Purpose |
|---|---|---|
| **Admissions & Applications** | `Bauhaven Admissions <admissions@bauhaven.com>` | Application confirmation & approvals |
| **Tasks & Cohort Notifications** | `Bauhaven Tasks <info@bauhaven.com>` | Task assignments, submissions, deadlines |
| **Requests & Permissions** | `Bauhaven Requests <info@bauhaven.com>` | Leave requests, access elevation |
| **General Platform Announcements** | `Bauhaven <info@bauhaven.com>` | System-wide updates |

---

## 4. How to Update in Edge Functions

In your Edge Function (`supabase/functions/<name>/index.ts`):
```typescript
import { sendEmail } from './email-helper.ts'; // or inline fetch to https://api.resend.com/emails

const template = await Deno.readTextFile(new URL('../../emails/transactional/task-assigned.html', import.meta.url));

const html = template
  .replaceAll('{{name}}', assigneeName)
  .replaceAll('{{task_title}}', task.title)
  .replaceAll('{{due_date}}', dueLabel)
  .replaceAll('{{instructions}}', task.instructions || 'Review instructions on the portal.')
  .replaceAll('{{portal_url}}', 'https://academy.bauhaven.com/tasks');

await fetch('https://api.resend.com/emails', {
  method: 'POST',
  headers: {
    Authorization: `Bearer ${resendApiKey}`,
    'Content-Type': 'application/json',
  },
  body: JSON.stringify({
    from: 'Bauhaven Tasks <info@bauhaven.com>',
    to: [assigneeEmail],
    subject: `New task assigned: ${task.title}`,
    html,
  }),
});
```
