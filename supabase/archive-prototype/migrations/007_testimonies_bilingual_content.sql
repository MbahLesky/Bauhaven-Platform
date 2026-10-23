-- =========================================================
-- Testimonies: let a testimony exist in French alone
-- =========================================================
--
-- `testimonies.content_en` was `text not null` while `content_fr` was nullable, which
-- encodes "every testimony is written in English, and French is an optional translation
-- of it". For editorial content that's right — a page ships in English first and gets
-- translated, which is exactly what `pages` and `portfolio_entries` do, and Admin-web's
-- Content Editor already enforces both languages before publishing.
--
-- A testimony is not editorial content. It's a person's own words about their own
-- experience, and `users.preferred_language` already allows 'fr' — so a French-speaking
-- student in Cameroon writing a French testimony had exactly two possible outcomes under
-- the old constraint: their words stored in a column named `content_en` (which the public
-- Site would then render as the English pull-quote, presenting French text to English
-- readers as though it were the translation), or a failed insert. Neither is acceptable
-- for a bilingual product whose primary market is bilingual.
--
-- So the constraint moves from "English is mandatory" to "at least one language is
-- present". A testimony written in French is a complete testimony with `content_en` null,
-- awaiting translation the same way a French translation used to await writing. Whoever
-- builds the curation screen decides whether to translate before publishing; that is an
-- editorial call, not a reason to refuse the submission.
--
-- Safe to apply: nothing reads `testimonies` yet. No curation screen exists in Admin-web,
-- the public Site isn't built, and `bauhaven-academy-web` shows a student only their own
-- rows. Existing rows all satisfy the new check, since they cannot have a null
-- `content_en` under the old one.

alter table testimonies alter column content_en drop not null;

-- At least one language, never a row with neither. Without this, dropping `not null`
-- would allow a testimony with no content at all.
alter table testimonies add constraint testimonies_content_present
  check (content_en is not null or content_fr is not null);
