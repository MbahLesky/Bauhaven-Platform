-- ============================================================================
-- Migration 0043: Unify Website Educational Offerings into Central Catalog
--
-- Founder Directive:
-- "Now, the bauhaven website has courses, bootcamps and others.
--  How can we unify those in the backend so the display under programs in admin?"
--
-- 1. Updates / seeds all courses, bootcamps, holiday programs, and career tracks
--    into public.offerings so they are centrally managed in Bauhaven Admin.
-- 2. Creates a default open cohort for each offering so admissions and enrolments
--    can be immediately assigned.
-- 3. Reconciles existing applications to link to their exact offering_id.
-- ============================================================================

-- Ensure digital-marketing-7e80c8f4 uses the canonical slug 'digital-marketing' if available
UPDATE public.offerings
SET slug = 'digital-marketing',
    title = 'Digital Marketing'
WHERE slug = 'digital-marketing-7e80c8f4'
  AND NOT EXISTS (SELECT 1 FROM public.offerings WHERE slug = 'digital-marketing');

-- Align existing bootcamp-program with data-analysis-for-research-projects if present
UPDATE public.offerings
SET slug = 'data-analysis-for-research-projects',
    title = 'Data Analysis for Research Projects Bootcamp'
WHERE slug = 'bootcamp-program'
  AND NOT EXISTS (SELECT 1 FROM public.offerings WHERE slug = 'data-analysis-for-research-projects');

-- Ensure internship-program has proper title and status
UPDATE public.offerings
SET title = 'Professional Tech & Design Internship',
    operational_status = 'active',
    is_accepting_applications = true,
    publication_status = 'published',
    default_duration_text = '3-6 Months'
WHERE slug = 'internship-program';

-- -----------------------------------------------------------------------------
-- 1. Seed / Upsert Offerings from Website Catalog
-- -----------------------------------------------------------------------------
INSERT INTO public.offerings (
  slug, title, offering_type, short_description, description, default_duration_text,
  operational_status, is_accepting_applications, publication_status
) VALUES (
  'graphics-design',
  'Graphics Design',
  'course',
  'Learn the fundamentals of visual communication and creative layout design to create stunning graphics for print and web.',
  'This course provides a comprehensive introduction to the world of graphic design. You will learn the core principles of visual communication, including typography, color theory, and layout design. The curriculum is designed to be hands-on, focusing on practical skills to create a wide range of materials such as posters, brochures, social media visuals, and logos. By the end of this course, you will be proficient in using industry-standard software to bring your creative ideas to life.',
  '6 months',
  'active',
  true,
  'published'
)
ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title,
  offering_type = EXCLUDED.offering_type,
  short_description = COALESCE(EXCLUDED.short_description, public.offerings.short_description),
  description = COALESCE(EXCLUDED.description, public.offerings.description),
  default_duration_text = COALESCE(EXCLUDED.default_duration_text, public.offerings.default_duration_text),
  operational_status = 'active',
  is_accepting_applications = true,
  publication_status = 'published';

INSERT INTO public.offerings (
  slug, title, offering_type, short_description, description, default_duration_text,
  operational_status, is_accepting_applications, publication_status
) VALUES (
  'brand-identity-design',
  'Brand & Identity Design',
  'course',
  'Master the art of brand and identity design, from initial concept to professional execution.',
  'This practical program is designed to take you from the fundamentals of visual communication to the professional execution of brand identity projects. You will learn how to use industry-standard tools to create memorable logos, cohesive brand assets, and effective marketing materials for both print and digital platforms. The course emphasizes a hands-on approach, enabling you to build a strong portfolio of brand design work.',
  '6 months',
  'active',
  true,
  'published'
)
ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title,
  offering_type = EXCLUDED.offering_type,
  short_description = COALESCE(EXCLUDED.short_description, public.offerings.short_description),
  description = COALESCE(EXCLUDED.description, public.offerings.description),
  default_duration_text = COALESCE(EXCLUDED.default_duration_text, public.offerings.default_duration_text),
  operational_status = 'active',
  is_accepting_applications = true,
  publication_status = 'published';

INSERT INTO public.offerings (
  slug, title, offering_type, short_description, description, default_duration_text,
  operational_status, is_accepting_applications, publication_status
) VALUES (
  'ui-ux-design',
  'UI & UX Design',
  'course',
  'Learn to design intuitive and visually appealing user-centered digital experiences for web and mobile platforms.',
  'In this course, you will dive into the world of User Interface (UI) and User Experience (UX) design. The curriculum is structured to provide a balance of creative interface design and practical usability principles. You will learn how to conduct user research, create wireframes and prototypes, and design functional and aesthetically pleasing digital products. This course will equip you with the skills to create meaningful and user-friendly experiences for websites and mobile applications.',
  '3 months',
  'active',
  true,
  'published'
)
ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title,
  offering_type = EXCLUDED.offering_type,
  short_description = COALESCE(EXCLUDED.short_description, public.offerings.short_description),
  description = COALESCE(EXCLUDED.description, public.offerings.description),
  default_duration_text = COALESCE(EXCLUDED.default_duration_text, public.offerings.default_duration_text),
  operational_status = 'active',
  is_accepting_applications = true,
  publication_status = 'published';

INSERT INTO public.offerings (
  slug, title, offering_type, short_description, description, default_duration_text,
  operational_status, is_accepting_applications, publication_status
) VALUES (
  'web-design-no-code',
  'Web Design (No Code)',
  'course',
  'Design and build beautiful, functional websites without writing a single line of code.',
  'This course is perfect for those who want to create professional websites without the need for coding. You will learn how to use popular platforms like WordPress and page builders like Elementor to design and launch fully functional websites. The course covers everything from initial setup and design to content management and optimization, empowering you to build websites for personal brands, small businesses, or portfolios.',
  '3 months',
  'active',
  true,
  'published'
)
ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title,
  offering_type = EXCLUDED.offering_type,
  short_description = COALESCE(EXCLUDED.short_description, public.offerings.short_description),
  description = COALESCE(EXCLUDED.description, public.offerings.description),
  default_duration_text = COALESCE(EXCLUDED.default_duration_text, public.offerings.default_duration_text),
  operational_status = 'active',
  is_accepting_applications = true,
  publication_status = 'published';

INSERT INTO public.offerings (
  slug, title, offering_type, short_description, description, default_duration_text,
  operational_status, is_accepting_applications, publication_status
) VALUES (
  'web-design-code',
  'Web Design (Code)',
  'course',
  'Learn to code and design modern, interactive websites using HTML, CSS, and JavaScript.',
  'This course provides a comprehensive introduction to web design with a focus on coding. You will learn the fundamental building blocks of the web, including HTML for structure, CSS for styling, and JavaScript for interactivity. The curriculum also covers modern frontend frameworks, enabling you to build responsive and dynamic websites from scratch. By the end of this course, you will have the skills to turn creative concepts into fully functional web experiences.',
  '6 months',
  'active',
  true,
  'published'
)
ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title,
  offering_type = EXCLUDED.offering_type,
  short_description = COALESCE(EXCLUDED.short_description, public.offerings.short_description),
  description = COALESCE(EXCLUDED.description, public.offerings.description),
  default_duration_text = COALESCE(EXCLUDED.default_duration_text, public.offerings.default_duration_text),
  operational_status = 'active',
  is_accepting_applications = true,
  publication_status = 'published';

INSERT INTO public.offerings (
  slug, title, offering_type, short_description, description, default_duration_text,
  operational_status, is_accepting_applications, publication_status
) VALUES (
  'web-developer',
  'Web Development',
  'course',
  'Become a full-stack web developer by mastering both front-end and back-end technologies.',
  'This comprehensive program is designed for aspiring web developers who want to build full-stack web applications. You will start with the basics of HTML, CSS, and JavaScript, then move on to back-end technologies, frameworks, and deployment. The course is project-based, allowing you to build real-world applications and gain hands-on experience. By the end of a program, you will have a strong portfolio and the skills to pursue a career as a web developer.',
  '6 months',
  'active',
  true,
  'published'
)
ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title,
  offering_type = EXCLUDED.offering_type,
  short_description = COALESCE(EXCLUDED.short_description, public.offerings.short_description),
  description = COALESCE(EXCLUDED.description, public.offerings.description),
  default_duration_text = COALESCE(EXCLUDED.default_duration_text, public.offerings.default_duration_text),
  operational_status = 'active',
  is_accepting_applications = true,
  publication_status = 'published';

INSERT INTO public.offerings (
  slug, title, offering_type, short_description, description, default_duration_text,
  operational_status, is_accepting_applications, publication_status
) VALUES (
  'mobile-app-developer',
  'Mobile App Developer',
  'course',
  'Learn to design, develop, and deploy mobile applications using the modern framework Flutter.',
  'This practical program will guide you through the entire mobile app development lifecycle. You will learn how to use Flutter to build beautiful and high-performance applications for both iOS and Android from a single codebase. The course covers everything from coding and UI/UX design to back-end integration and publishing your app to the app stores. You will gain the skills to turn your app ideas into reality.',
  '6 months',
  'active',
  true,
  'published'
)
ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title,
  offering_type = EXCLUDED.offering_type,
  short_description = COALESCE(EXCLUDED.short_description, public.offerings.short_description),
  description = COALESCE(EXCLUDED.description, public.offerings.description),
  default_duration_text = COALESCE(EXCLUDED.default_duration_text, public.offerings.default_duration_text),
  operational_status = 'active',
  is_accepting_applications = true,
  publication_status = 'published';

INSERT INTO public.offerings (
  slug, title, offering_type, short_description, description, default_duration_text,
  operational_status, is_accepting_applications, publication_status
) VALUES (
  'video-editing',
  'Video Editing',
  'course',
  'Master the art of video editing to create professional-quality videos for a variety of digital platforms.',
  'This hands-on program will teach you the art and technique of video editing. You will learn to use industry-standard software to edit a wide range of content, including social media clips, vlogs, and branded videos. The course covers everything from basic cuts and transitions to advanced color grading and motion graphics. You will develop the skills to tell compelling stories through video and produce polished, professional content.',
  '3 months',
  'active',
  true,
  'published'
)
ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title,
  offering_type = EXCLUDED.offering_type,
  short_description = COALESCE(EXCLUDED.short_description, public.offerings.short_description),
  description = COALESCE(EXCLUDED.description, public.offerings.description),
  default_duration_text = COALESCE(EXCLUDED.default_duration_text, public.offerings.default_duration_text),
  operational_status = 'active',
  is_accepting_applications = true,
  publication_status = 'published';

INSERT INTO public.offerings (
  slug, title, offering_type, short_description, description, default_duration_text,
  operational_status, is_accepting_applications, publication_status
) VALUES (
  'digital-marketing',
  'Digital Marketing',
  'course',
  'Learn the fundamentals of digital marketing and how to create effective campaigns across various channels.',
  'This program provides a comprehensive overview of digital marketing. You will learn how to create and execute marketing campaigns on social media, search engines, and email. The course covers a wide range of topics, including content creation, SEO, advertising, and analytics. You will gain practical skills in using industry-standard tools to create ads, build marketing funnels, and measure the success of your campaigns.',
  '6 months',
  'active',
  true,
  'published'
)
ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title,
  offering_type = EXCLUDED.offering_type,
  short_description = COALESCE(EXCLUDED.short_description, public.offerings.short_description),
  description = COALESCE(EXCLUDED.description, public.offerings.description),
  default_duration_text = COALESCE(EXCLUDED.default_duration_text, public.offerings.default_duration_text),
  operational_status = 'active',
  is_accepting_applications = true,
  publication_status = 'published';

INSERT INTO public.offerings (
  slug, title, offering_type, short_description, description, default_duration_text,
  operational_status, is_accepting_applications, publication_status
) VALUES (
  'search-engine-optimization',
  'Search Engine Optimization',
  'course',
  'Master the art of Search Engine Optimization (SEO) to boost website rankings and drive organic traffic.',
  'This program is designed to teach you the ins and outs of Search Engine Optimization. You will learn how to conduct keyword research, optimize website content, and build high-quality backlinks. The course covers both on-page and off-page SEO strategies, as well as technical SEO and analytics. You will gain the skills to improve a website''s visibility in search engine results and attract more organic traffic.',
  '2 months',
  'active',
  true,
  'published'
)
ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title,
  offering_type = EXCLUDED.offering_type,
  short_description = COALESCE(EXCLUDED.short_description, public.offerings.short_description),
  description = COALESCE(EXCLUDED.description, public.offerings.description),
  default_duration_text = COALESCE(EXCLUDED.default_duration_text, public.offerings.default_duration_text),
  operational_status = 'active',
  is_accepting_applications = true,
  publication_status = 'published';

INSERT INTO public.offerings (
  slug, title, offering_type, short_description, description, default_duration_text,
  operational_status, is_accepting_applications, publication_status
) VALUES (
  'office-productivity',
  'Office Productivity',
  'course',
  'Boost your productivity with essential office skills and tools for today''s workplace.',
  'This program is designed to help you become more efficient and effective in the modern workplace. You will learn how to use a variety of office productivity tools to create professional documents, manage data, and collaborate with others. The course covers topics such as word processing, spreadsheets, presentation software, and online collaboration tools. You will gain the skills to streamline your workflow and improve your overall productivity.',
  '3 months',
  'active',
  true,
  'published'
)
ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title,
  offering_type = EXCLUDED.offering_type,
  short_description = COALESCE(EXCLUDED.short_description, public.offerings.short_description),
  description = COALESCE(EXCLUDED.description, public.offerings.description),
  default_duration_text = COALESCE(EXCLUDED.default_duration_text, public.offerings.default_duration_text),
  operational_status = 'active',
  is_accepting_applications = true,
  publication_status = 'published';

INSERT INTO public.offerings (
  slug, title, offering_type, short_description, description, default_duration_text,
  operational_status, is_accepting_applications, publication_status
) VALUES (
  'computer-essentials',
  'Computer Essentials',
  'course',
  'Master the essential computer skills needed for study, work, and everyday life.',
  'This course is designed for beginners who want to build a strong foundation in computer literacy. You will learn the basics of computer hardware and software, file management, and internet safety. The course also covers essential productivity tools for creating documents, spreadsheets, and presentations. By the end of this course, you will have the confidence and skills to use a computer effectively for personal, academic, and professional tasks.',
  '3 months',
  'active',
  true,
  'published'
)
ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title,
  offering_type = EXCLUDED.offering_type,
  short_description = COALESCE(EXCLUDED.short_description, public.offerings.short_description),
  description = COALESCE(EXCLUDED.description, public.offerings.description),
  default_duration_text = COALESCE(EXCLUDED.default_duration_text, public.offerings.default_duration_text),
  operational_status = 'active',
  is_accepting_applications = true,
  publication_status = 'published';

INSERT INTO public.offerings (
  slug, title, offering_type, short_description, description, default_duration_text,
  operational_status, is_accepting_applications, publication_status
) VALUES (
  'cyber-security-ai',
  'Cyber Security & AI',
  'course',
  'Learn practical cyber security, ethical hacking basics, and AI-powered security workflows for modern digital systems.',
  'This course introduces students to the foundations of cyber security and the growing role of artificial intelligence in protecting digital systems. You will learn how networks, applications, and users are attacked, how to identify vulnerabilities, and how to apply defensive practices. The program combines practical security labs with AI-assisted monitoring, analysis, and automation so learners can understand both traditional security operations and modern intelligent threat detection.',
  '6 months',
  'active',
  true,
  'published'
)
ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title,
  offering_type = EXCLUDED.offering_type,
  short_description = COALESCE(EXCLUDED.short_description, public.offerings.short_description),
  description = COALESCE(EXCLUDED.description, public.offerings.description),
  default_duration_text = COALESCE(EXCLUDED.default_duration_text, public.offerings.default_duration_text),
  operational_status = 'active',
  is_accepting_applications = true,
  publication_status = 'published';

INSERT INTO public.offerings (
  slug, title, offering_type, short_description, description, default_duration_text,
  operational_status, is_accepting_applications, publication_status
) VALUES (
  'data-science-machine-learning',
  'Data Science & Machine Learning',
  'course',
  'Learn data analysis, Python, machine learning fundamentals, and practical AI model workflows for real-world projects.',
  'This course teaches students how to work with data from collection and cleaning to analysis, visualization, and machine learning. You will learn Python programming for data work, explore statistics and data storytelling, and build practical machine learning models. The program focuses on hands-on projects that help learners turn raw data into insights and create portfolio-ready AI and machine learning solutions.',
  '6 months',
  'active',
  true,
  'published'
)
ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title,
  offering_type = EXCLUDED.offering_type,
  short_description = COALESCE(EXCLUDED.short_description, public.offerings.short_description),
  description = COALESCE(EXCLUDED.description, public.offerings.description),
  default_duration_text = COALESCE(EXCLUDED.default_duration_text, public.offerings.default_duration_text),
  operational_status = 'active',
  is_accepting_applications = true,
  publication_status = 'published';

INSERT INTO public.offerings (
  slug, title, offering_type, short_description, description, default_duration_text,
  operational_status, is_accepting_applications, publication_status
) VALUES (
  'mobile-graphic-design',
  '7-Days Practical Training in Mobile Graphic Design',
  'bootcamp',
  'Most beginners let the lack of an expensive computer stop them from learning design. This intensive 7-day online bootcamp is built to eliminate that barrier. Facilitated by Azeh Tenly M. and Mbah Lesky (Lespa), this practical training will teach you the core principles of visual hierarchy, color theory, and typography using powerful mobile design tools like Canva, PixelLab, and Jitter.',
  'Most beginners let the lack of an expensive computer stop them from learning design. This intensive 7-day online bootcamp is built to eliminate that barrier. Facilitated by Azeh Tenly M. and Mbah Lesky (Lespa), this practical training will teach you the core principles of visual hierarchy, color theory, and typography using powerful mobile design tools like Canva, PixelLab, and Jitter.',
  '7 Days',
  'active',
  true,
  'published'
)
ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title,
  offering_type = EXCLUDED.offering_type,
  short_description = COALESCE(EXCLUDED.short_description, public.offerings.short_description),
  description = COALESCE(EXCLUDED.description, public.offerings.description),
  default_duration_text = COALESCE(EXCLUDED.default_duration_text, public.offerings.default_duration_text),
  operational_status = 'active',
  is_accepting_applications = true,
  publication_status = 'published';

INSERT INTO public.offerings (
  slug, title, offering_type, short_description, description, default_duration_text,
  operational_status, is_accepting_applications, publication_status
) VALUES (
  'graphics-design-made-simple',
  'Graphics Design Made Simple - A 3 Day Practical Bootcamp',
  'bootcamp',
  'Learn practical graphic design by creating real flyers, logos, brand styles, and mockups with step-by-step support.',
  'Learn practical graphic design by creating real flyers, logos, brand styles, and mockups with step-by-step support.',
  '3 Days',
  'active',
  true,
  'published'
)
ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title,
  offering_type = EXCLUDED.offering_type,
  short_description = COALESCE(EXCLUDED.short_description, public.offerings.short_description),
  description = COALESCE(EXCLUDED.description, public.offerings.description),
  default_duration_text = COALESCE(EXCLUDED.default_duration_text, public.offerings.default_duration_text),
  operational_status = 'active',
  is_accepting_applications = true,
  publication_status = 'published';

INSERT INTO public.offerings (
  slug, title, offering_type, short_description, description, default_duration_text,
  operational_status, is_accepting_applications, publication_status
) VALUES (
  'data-analysis-for-research-projects',
  'Data Analysis for Research Projects Bootcamp',
  'bootcamp',
  'Learn how to collect, organize, analyze, and interpret data using tools like Excel and SPSS so you can confidently handle the data analysis part of your academic project.',
  'Learn how to collect, organize, analyze, and interpret data using tools like Excel and SPSS so you can confidently handle the data analysis part of your academic project.',
  'Project-based practical sessions',
  'active',
  true,
  'published'
)
ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title,
  offering_type = EXCLUDED.offering_type,
  short_description = COALESCE(EXCLUDED.short_description, public.offerings.short_description),
  description = COALESCE(EXCLUDED.description, public.offerings.description),
  default_duration_text = COALESCE(EXCLUDED.default_duration_text, public.offerings.default_duration_text),
  operational_status = 'active',
  is_accepting_applications = true,
  publication_status = 'published';

INSERT INTO public.offerings (
  slug, title, offering_type, short_description, description, default_duration_text,
  operational_status, is_accepting_applications, publication_status
) VALUES (
  'holiday-computer-fundamentals',
  'Computer Fundamentals',
  'holiday_program',
  'Master the basics of computing and learn essential computer skills.',
  'Master the basics of computing and learn essential computer skills.

Highlights:
- Computer basics & components
- How to manage files & folders
- Setting up & troubleshooting
- Operating system navigation',
  '8 Weeks',
  'active',
  true,
  'published'
)
ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title,
  offering_type = EXCLUDED.offering_type,
  short_description = COALESCE(EXCLUDED.short_description, public.offerings.short_description),
  description = COALESCE(EXCLUDED.description, public.offerings.description),
  default_duration_text = COALESCE(EXCLUDED.default_duration_text, public.offerings.default_duration_text),
  operational_status = 'active',
  is_accepting_applications = true,
  publication_status = 'published';

INSERT INTO public.offerings (
  slug, title, offering_type, short_description, description, default_duration_text,
  operational_status, is_accepting_applications, publication_status
) VALUES (
  'holiday-typing-digital-skills',
  'Typing & Digital Skills',
  'holiday_program',
  'Learn to type fast and confidently while developing essential digital competencies.',
  'Learn to type fast and confidently while developing essential digital competencies.

Highlights:
- Fast & accurate typing techniques
- Keyboard shortcuts & efficiency
- Mouse & trackpad mastery
- Digital literacy fundamentals',
  '8 Weeks',
  'active',
  true,
  'published'
)
ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title,
  offering_type = EXCLUDED.offering_type,
  short_description = COALESCE(EXCLUDED.short_description, public.offerings.short_description),
  description = COALESCE(EXCLUDED.description, public.offerings.description),
  default_duration_text = COALESCE(EXCLUDED.default_duration_text, public.offerings.default_duration_text),
  operational_status = 'active',
  is_accepting_applications = true,
  publication_status = 'published';

INSERT INTO public.offerings (
  slug, title, offering_type, short_description, description, default_duration_text,
  operational_status, is_accepting_applications, publication_status
) VALUES (
  'holiday-internet-online-skills',
  'Internet & Online Skills',
  'holiday_program',
  'Navigate the internet safely and effectively while learning essential online skills.',
  'Navigate the internet safely and effectively while learning essential online skills.

Highlights:
- Safe web browsing practices
- Download & upload resources
- Effective search techniques
- Online safety & digital citizenship',
  '8 Weeks',
  'active',
  true,
  'published'
)
ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title,
  offering_type = EXCLUDED.offering_type,
  short_description = COALESCE(EXCLUDED.short_description, public.offerings.short_description),
  description = COALESCE(EXCLUDED.description, public.offerings.description),
  default_duration_text = COALESCE(EXCLUDED.default_duration_text, public.offerings.default_duration_text),
  operational_status = 'active',
  is_accepting_applications = true,
  publication_status = 'published';

INSERT INTO public.offerings (
  slug, title, offering_type, short_description, description, default_duration_text,
  operational_status, is_accepting_applications, publication_status
) VALUES (
  'holiday-create-edit-documents',
  'Create & Edit Documents',
  'holiday_program',
  'Create professional documents, spreadsheets, and presentations from scratch.',
  'Create professional documents, spreadsheets, and presentations from scratch.

Highlights:
- Document creation & formatting
- Spreadsheet fundamentals
- Data entry & organization
- Presentation design basics',
  '8 Weeks',
  'active',
  true,
  'published'
)
ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title,
  offering_type = EXCLUDED.offering_type,
  short_description = COALESCE(EXCLUDED.short_description, public.offerings.short_description),
  description = COALESCE(EXCLUDED.description, public.offerings.description),
  default_duration_text = COALESCE(EXCLUDED.default_duration_text, public.offerings.default_duration_text),
  operational_status = 'active',
  is_accepting_applications = true,
  publication_status = 'published';

INSERT INTO public.offerings (
  slug, title, offering_type, short_description, description, default_duration_text,
  operational_status, is_accepting_applications, publication_status
) VALUES (
  'holiday-computer-software',
  'Computer Software Essentials',
  'holiday_program',
  'Learn software installation, management, and basic troubleshooting.',
  'Learn software installation, management, and basic troubleshooting.

Highlights:
- Download & install software safely
- Software updates & maintenance
- Antivirus & security basics
- Common problem solving',
  '8 Weeks',
  'active',
  true,
  'published'
)
ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title,
  offering_type = EXCLUDED.offering_type,
  short_description = COALESCE(EXCLUDED.short_description, public.offerings.short_description),
  description = COALESCE(EXCLUDED.description, public.offerings.description),
  default_duration_text = COALESCE(EXCLUDED.default_duration_text, public.offerings.default_duration_text),
  operational_status = 'active',
  is_accepting_applications = true,
  publication_status = 'published';

INSERT INTO public.offerings (
  slug, title, offering_type, short_description, description, default_duration_text,
  operational_status, is_accepting_applications, publication_status
) VALUES (
  'holiday-graphic-design',
  'Graphic Design Basics',
  'holiday_program',
  'Create stunning visual designs including posters, flyers, and graphics.',
  'Create stunning visual designs including posters, flyers, and graphics.

Highlights:
- Design principles & color theory
- Poster & flyer creation
- Photo editing fundamentals
- Visual layout & typography',
  '8 Weeks',
  'active',
  true,
  'published'
)
ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title,
  offering_type = EXCLUDED.offering_type,
  short_description = COALESCE(EXCLUDED.short_description, public.offerings.short_description),
  description = COALESCE(EXCLUDED.description, public.offerings.description),
  default_duration_text = COALESCE(EXCLUDED.default_duration_text, public.offerings.default_duration_text),
  operational_status = 'active',
  is_accepting_applications = true,
  publication_status = 'published';

INSERT INTO public.offerings (
  slug, title, offering_type, short_description, description, default_duration_text,
  operational_status, is_accepting_applications, publication_status
) VALUES (
  'holiday-website-design',
  'Website Design',
  'holiday_program',
  'Design and build simple, functional websites with modern tools.',
  'Design and build simple, functional websites with modern tools.

Highlights:
- Web design fundamentals
- User interface principles
- Responsive design basics
- Website publishing & hosting',
  '8 Weeks',
  'active',
  true,
  'published'
)
ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title,
  offering_type = EXCLUDED.offering_type,
  short_description = COALESCE(EXCLUDED.short_description, public.offerings.short_description),
  description = COALESCE(EXCLUDED.description, public.offerings.description),
  default_duration_text = COALESCE(EXCLUDED.default_duration_text, public.offerings.default_duration_text),
  operational_status = 'active',
  is_accepting_applications = true,
  publication_status = 'published';

INSERT INTO public.offerings (
  slug, title, offering_type, short_description, description, default_duration_text,
  operational_status, is_accepting_applications, publication_status
) VALUES (
  'holiday-ai-digital-literacy',
  'Learn AI Effectively',
  'holiday_program',
  'Understand and harness the power of AI tools for productivity and creativity.',
  'Understand and harness the power of AI tools for productivity and creativity.

Highlights:
- Introduction to Artificial Intelligence
- AI tools & applications
- Prompt engineering basics
- Responsible AI usage & ethics',
  '8 Weeks',
  'active',
  true,
  'published'
)
ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title,
  offering_type = EXCLUDED.offering_type,
  short_description = COALESCE(EXCLUDED.short_description, public.offerings.short_description),
  description = COALESCE(EXCLUDED.description, public.offerings.description),
  default_duration_text = COALESCE(EXCLUDED.default_duration_text, public.offerings.default_duration_text),
  operational_status = 'active',
  is_accepting_applications = true,
  publication_status = 'published';

INSERT INTO public.offerings (
  slug, title, offering_type, short_description, description, default_duration_text,
  operational_status, is_accepting_applications, publication_status
) VALUES (
  'career-track-web-developer',
  'Web Developer Career Track',
  'program',
  'Comprehensive learning path to take you from beginner to job-ready Web Developer.',
  'Comprehensive learning path to take you from beginner to job-ready Web Developer.',
  '6 Months',
  'active',
  true,
  'published'
)
ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title,
  offering_type = EXCLUDED.offering_type,
  short_description = COALESCE(EXCLUDED.short_description, public.offerings.short_description),
  description = COALESCE(EXCLUDED.description, public.offerings.description),
  default_duration_text = COALESCE(EXCLUDED.default_duration_text, public.offerings.default_duration_text),
  operational_status = 'active',
  is_accepting_applications = true,
  publication_status = 'published';

INSERT INTO public.offerings (
  slug, title, offering_type, short_description, description, default_duration_text,
  operational_status, is_accepting_applications, publication_status
) VALUES (
  'career-track-app-developer',
  'Mobile App Developer Career Track',
  'program',
  'Comprehensive learning path to take you from beginner to job-ready Mobile App Developer.',
  'Comprehensive learning path to take you from beginner to job-ready Mobile App Developer.',
  '6 Months',
  'active',
  true,
  'published'
)
ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title,
  offering_type = EXCLUDED.offering_type,
  short_description = COALESCE(EXCLUDED.short_description, public.offerings.short_description),
  description = COALESCE(EXCLUDED.description, public.offerings.description),
  default_duration_text = COALESCE(EXCLUDED.default_duration_text, public.offerings.default_duration_text),
  operational_status = 'active',
  is_accepting_applications = true,
  publication_status = 'published';

INSERT INTO public.offerings (
  slug, title, offering_type, short_description, description, default_duration_text,
  operational_status, is_accepting_applications, publication_status
) VALUES (
  'career-track-graphics-designer',
  'Graphics Designer Career Track',
  'program',
  'Comprehensive learning path to take you from beginner to job-ready Graphics Designer.',
  'Comprehensive learning path to take you from beginner to job-ready Graphics Designer.',
  '6 Months',
  'active',
  true,
  'published'
)
ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title,
  offering_type = EXCLUDED.offering_type,
  short_description = COALESCE(EXCLUDED.short_description, public.offerings.short_description),
  description = COALESCE(EXCLUDED.description, public.offerings.description),
  default_duration_text = COALESCE(EXCLUDED.default_duration_text, public.offerings.default_duration_text),
  operational_status = 'active',
  is_accepting_applications = true,
  publication_status = 'published';

INSERT INTO public.offerings (
  slug, title, offering_type, short_description, description, default_duration_text,
  operational_status, is_accepting_applications, publication_status
) VALUES (
  'career-track-digital-marketer',
  'Digital Marketer Career Track',
  'program',
  'Comprehensive learning path to take you from beginner to job-ready Digital Marketer.',
  'Comprehensive learning path to take you from beginner to job-ready Digital Marketer.',
  '6 Months',
  'active',
  true,
  'published'
)
ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title,
  offering_type = EXCLUDED.offering_type,
  short_description = COALESCE(EXCLUDED.short_description, public.offerings.short_description),
  description = COALESCE(EXCLUDED.description, public.offerings.description),
  default_duration_text = COALESCE(EXCLUDED.default_duration_text, public.offerings.default_duration_text),
  operational_status = 'active',
  is_accepting_applications = true,
  publication_status = 'published';

-- -----------------------------------------------------------------------------
-- 2. Create Default Active Cohort for Each Offering
-- -----------------------------------------------------------------------------
INSERT INTO public.cohorts (
  offering_id, code, name, status, starts_at, delivery_mode
)
SELECT
  o.id,
  'INT-2026',
  'Intake 2026-A',
  'open',
  CURRENT_DATE,
  'in_person'
FROM public.offerings o
WHERE NOT EXISTS (
  SELECT 1 FROM public.cohorts c WHERE c.offering_id = o.id
)
ON CONFLICT (offering_id, code) DO NOTHING;

-- -----------------------------------------------------------------------------
-- 3. Reconcile Applications to Point to the Exact Offering
-- -----------------------------------------------------------------------------

-- Exact course title matches
UPDATE public.applications a
SET offering_id = o.id
FROM public.offerings o
WHERE lower(trim(a.course)) = lower(trim(o.title))
  AND (a.offering_id IS NULL OR a.offering_id = 'ec6d9fc9-60e0-4e84-968f-91cb9dd66a10');

-- Specific common aliases and courses
UPDATE public.applications a
SET offering_id = o.id
FROM public.offerings o
WHERE o.slug = 'ui-ux-design'
  AND lower(a.course) LIKE '%ui%'
  AND (a.offering_id IS NULL OR a.offering_id = 'ec6d9fc9-60e0-4e84-968f-91cb9dd66a10');

UPDATE public.applications a
SET offering_id = o.id
FROM public.offerings o
WHERE o.slug = 'web-developer'
  AND (lower(a.course) LIKE '%web dev%' OR lower(a.course) = 'web development')
  AND (a.offering_id IS NULL OR a.offering_id = 'ec6d9fc9-60e0-4e84-968f-91cb9dd66a10');

UPDATE public.applications a
SET offering_id = o.id
FROM public.offerings o
WHERE o.slug = 'web-design-no-code'
  AND lower(a.course) LIKE '%no code%'
  AND (a.offering_id IS NULL OR a.offering_id = 'ec6d9fc9-60e0-4e84-968f-91cb9dd66a10');

UPDATE public.applications a
SET offering_id = o.id
FROM public.offerings o
WHERE o.slug = 'web-design-code'
  AND lower(a.course) LIKE '%web design (code)%'
  AND (a.offering_id IS NULL OR a.offering_id = 'ec6d9fc9-60e0-4e84-968f-91cb9dd66a10');

UPDATE public.applications a
SET offering_id = o.id
FROM public.offerings o
WHERE o.slug = 'mobile-app-developer'
  AND lower(a.course) LIKE '%mobile app%'
  AND (a.offering_id IS NULL OR a.offering_id = 'ec6d9fc9-60e0-4e84-968f-91cb9dd66a10');

UPDATE public.applications a
SET offering_id = o.id
FROM public.offerings o
WHERE o.slug = 'mobile-graphic-design'
  AND lower(a.course) LIKE '%mobile graphic%'
  AND (a.offering_id IS NULL OR a.offering_id = 'ec6d9fc9-60e0-4e84-968f-91cb9dd66a10');

UPDATE public.applications a
SET offering_id = o.id
FROM public.offerings o
WHERE o.slug = 'graphics-design-made-simple'
  AND (lower(a.course) LIKE '%simple%' OR lower(a.course) LIKE '%3 day%')
  AND (a.offering_id IS NULL OR a.offering_id = 'ec6d9fc9-60e0-4e84-968f-91cb9dd66a10');

UPDATE public.applications a
SET offering_id = o.id
FROM public.offerings o
WHERE o.slug = 'graphics-design'
  AND lower(a.course) LIKE '%graphic%'
  AND lower(a.course) NOT LIKE '%mobile%'
  AND lower(a.course) NOT LIKE '%simple%'
  AND (a.offering_id IS NULL OR a.offering_id = 'ec6d9fc9-60e0-4e84-968f-91cb9dd66a10');

UPDATE public.applications a
SET offering_id = o.id
FROM public.offerings o
WHERE o.slug = 'data-analysis-for-research-projects'
  AND lower(a.course) LIKE '%data analysis%'
  AND (a.offering_id IS NULL OR a.offering_id = 'ec6d9fc9-60e0-4e84-968f-91cb9dd66a10');

UPDATE public.applications a
SET offering_id = o.id
FROM public.offerings o
WHERE o.slug = 'cyber-security-ai'
  AND (lower(a.course) LIKE '%cyber%' OR lower(a.course) LIKE '%security%')
  AND (a.offering_id IS NULL OR a.offering_id = 'ec6d9fc9-60e0-4e84-968f-91cb9dd66a10');

UPDATE public.applications a
SET offering_id = o.id
FROM public.offerings o
WHERE o.slug = 'data-science-machine-learning'
  AND (lower(a.course) LIKE '%machine learning%' OR lower(a.course) LIKE '%data science%')
  AND (a.offering_id IS NULL OR a.offering_id = 'ec6d9fc9-60e0-4e84-968f-91cb9dd66a10');

UPDATE public.applications a
SET offering_id = o.id
FROM public.offerings o
WHERE o.slug = 'video-editing'
  AND (lower(a.course) LIKE '%video%' OR lower(a.course) LIKE '%motion%')
  AND (a.offering_id IS NULL OR a.offering_id = 'ec6d9fc9-60e0-4e84-968f-91cb9dd66a10');

UPDATE public.applications a
SET offering_id = o.id
FROM public.offerings o
WHERE o.slug = 'digital-marketing'
  AND lower(a.course) LIKE '%marketing%'
  AND (a.offering_id IS NULL OR a.offering_id = 'ec6d9fc9-60e0-4e84-968f-91cb9dd66a10');

UPDATE public.applications a
SET offering_id = o.id
FROM public.offerings o
WHERE o.slug = 'office-productivity'
  AND (lower(a.course) LIKE '%office%' OR lower(a.course) LIKE '%productivity%')
  AND (a.offering_id IS NULL OR a.offering_id = 'ec6d9fc9-60e0-4e84-968f-91cb9dd66a10');

UPDATE public.applications a
SET offering_id = o.id
FROM public.offerings o
WHERE o.slug = 'computer-essentials'
  AND lower(a.course) LIKE '%essentials%'
  AND (a.offering_id IS NULL OR a.offering_id = 'ec6d9fc9-60e0-4e84-968f-91cb9dd66a10');

UPDATE public.applications a
SET offering_id = o.id
FROM public.offerings o
WHERE o.slug = 'brand-identity-design'
  AND lower(a.course) LIKE '%brand%'
  AND (a.offering_id IS NULL OR a.offering_id = 'ec6d9fc9-60e0-4e84-968f-91cb9dd66a10');

UPDATE public.applications a
SET offering_id = o.id
FROM public.offerings o
WHERE o.slug = 'search-engine-optimization'
  AND (lower(a.course) LIKE '%seo%' OR lower(a.course) LIKE '%search engine%')
  AND (a.offering_id IS NULL OR a.offering_id = 'ec6d9fc9-60e0-4e84-968f-91cb9dd66a10');

-- Fallback for internship program applications
UPDATE public.applications a
SET offering_id = o.id
FROM public.offerings o
WHERE o.slug = 'internship-program'
  AND a.program = 'internship-program'
  AND a.offering_id IS NULL;
