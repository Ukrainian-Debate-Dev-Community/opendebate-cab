# Changelog

## v0.8.0 - 2026-11-24

6 features, 2 fixes, 1 refactor, 3 chore; breaking: 0

### Features

- public: the header like the design, with a Menu on phones (#85) by @merv1n34k
- cab: the owner pages laid out like the others (#84) by @merv1n34k
- cab: the admin page like the others (#80) by @merv1n34k
- cab: My page and the session page laid out like the club page (#76) by @merv1n34k
- the clubs page like the design; phones skip the key numbers (#79) by @merv1n34k
- public: the calendar like the design, with a month grid on phones (#78) by @merv1n34k

### Fixes

- cab: My page keeps its figures on phones (#83) by @merv1n34k
- ui: the phone field stays on one line (#81) by @merv1n34k

### Other

- refactor: one copy of each style; the public site without the ua- prefix (#82) by @merv1n34k
- chore(dev): dev:up fetches the deps and says when nix is missing (#77) by @merv1n34k
- chore(ui): every size, gap and radius from the tokens (#74) by @merv1n34k
- chore(deps): bump phoenix to 1.8.17 for two HIGH advisories (#75) by @merv1n34k

### Contributors

- @merv1n34k: 12 commits

## v0.7.0 - 2026-11-21

3 features, 1 chore; breaking: 0

### Features

- M5 layout - one look for cab and the public site (#72) by @merv1n34k
- ui: components on the scale - targets, field edges, states in words (#71) by @merv1n34k
- ui: M5 foundation - colours from three inputs, one type and space scale (#70) by @merv1n34k

### Other

- chore(deps): bump phoenix_live_view to 1.2.14 for CVE-2026-126334 (#73) by @merv1n34k

### Contributors

- @merv1n34k: 4 commits

## v0.6.1 - 2026-11-20

1 feature; breaking: 0

### Features

- tenant theme and legal texts from the tenant folder (#69) by @merv1n34k

### Contributors

- @merv1n34k: 1 commit

## v0.6.0 - 2026-11-19

6 features, 1 fix, 1 chore; breaking: 0

### Features

- public: news posts in several languages (#68) by @merv1n34k
- public: preview a news post before saving or publishing (#67) by @merv1n34k
- public: show a drawing on news covers without an image (#64) by @merv1n34k
- photo collages in news and a full-screen viewer (#63) by @merv1n34k
- a rich text editor for news, bodies as sanitised HTML (#62) by @merv1n34k
- public: a news section with a featured story, cards and articles (#61) by @merv1n34k

### Fixes

- public: romanise Cyrillic titles into news slugs (#65) by @merv1n34k

### Other

- chore(deps): bump idna to 8.0.0 for CVE-2026-117678 (#66) by @merv1n34k

### Contributors

- @merv1n34k: 8 commits

## v0.5.0 - 2026-11-18

2 features, 1 fix, 2 chore; breaking: 0

### Features

- ui: apps/ui - one set of tokens, one stylesheet, the components both apps share (#57) by @merv1n34k
- the dev stack runs cab and the public site from a fresh checkout (#54) by @merv1n34k

### Fixes

- public: a decline reason that is too long is refused, not dropped (#53) by @merv1n34k

### Other

- chore: bump plug to 1.20.4 and fix a dated public test (#59) by @merv1n34k
- chore(deps): bump ecto to 3.14.3 for CVE-2026-118391 (#58) by @merv1n34k

### Contributors

- @merv1n34k: 5 commits

## v0.4.0 - 2026-10-31

4 features, 2 fixes, 2 chore; breaking: 0

### Features

- the image runs cab and the public site (the full release) (#52) by @merv1n34k
- cab: the home and sign-in wording comes from the operator (#47) by @merv1n34k
- public: the tenant's own pages, the about page among them (#49) by @merv1n34k
- public: the public site as apps/public, its content from the tenant (#48) by @merv1n34k

### Fixes

- cab: field errors and browser checks in the club and session forms (#44) by @merv1n34k
- cab: sign-in never returns to a look-alike address (#45) by @merv1n34k

### Other

- chore(deps): bump phoenix_html to 4.4.0 for CVE-2026-117645 (#50) by @merv1n34k
- chore(deps): bump bandit to 1.14.1 for CVE-2026-116078 (#46) by @merv1n34k

### Contributors

- @merv1n34k: 8 commits

## v0.3.0 - 2026-10-27

3 features, 1 fix, 2 chore; breaking: 0

### Features

- cab: the head adds people only within the participant limit (#42) by @merv1n34k
- cab: participant limit for sessions (#41) by @merv1n34k
- cab: native date and time pickers in the account's zone (#39) by @merv1n34k

### Fixes

- cab: the registration form button only on club and session pages (#38) by @merv1n34k

### Other

- chore(deps): bump jose to 1.11.13 for new advisories (#43) by @merv1n34k
- chore(deps): bump bandit to 1.14.0 for CVE-2026-115269 (#40) by @merv1n34k

### Contributors

- @merv1n34k: 6 commits

## v0.2.3 - 2026-10-26

1 fix; breaking: 0

### Fixes

- cab: a sign-in returns only where that sign-in asked (#37) by @merv1n34k

### Contributors

- @merv1n34k: 1 commit

## v0.2.2 - 2026-10-24

1 feature; breaking: 0

### Features

- cab: contact-field helpers as a script other sites can load (#36) by @merv1n34k

### Contributors

- @merv1n34k: 1 commit

## v0.2.1 - 2026-10-24

1 feature; breaking: 0

### Features

- cab: sign-in can return to the deployment's sibling sites (#35) by @merv1n34k

### Contributors

- @merv1n34k: 1 commit

## v0.2.0 - 2026-10-24

11 features, 6 fixes, 1 chore; breaking: 0

### Features

- cab: contact fields checked as typed, errors on leaving the field (#34) by @merv1n34k
- cab: phone, e-mail and telegram fields, checked and formatted (#30) by @merv1n34k
- cab: registration as a section on the club page (#20) by @merv1n34k
- cab: session results with points, motion details and a share card (#26) by @merv1n34k
- cab: session pages show the people who play, not team names (#25) by @merv1n34k
- cab: share a room as a picture or text, click to copy (#23) by @merv1n34k
- cab: club speakers and adjudicators across all sessions (#29) by @merv1n34k
- cab: step through standings sessions like the room count (#27) by @merv1n34k
- cab: members' saved answers, join request asks member fields (#19) by @merv1n34k
- forms: ask each registration field of guests, members or both (#16) by @merv1n34k
- cab: short links as a service for any target (#21) by @merv1n34k

### Fixes

- deps: fetch mdex's native library from its mirror (#33) by @merv1n34k
- ci: fetch tailwind with curl in the image build (#32) by @merv1n34k
- cab: my page and admin in the menu inside a club too (#24) by @merv1n34k
- deps: plug_crypto 2.2.1 (CVE-2026-105963) (#28) by @merv1n34k
- cab: a register button in the club list (#18) by @merv1n34k
- cab: nearest session, sessions by date, no register in sidebar (#17) by @merv1n34k

### Other

- chore(deps): opendebate-engine v1.5.0 (#31) by @merv1n34k

### Contributors

- @merv1n34k: 18 commits

## v0.1.0 - 2026-10-19

8 features, 3 fixes, 1 test, 3 chore; breaking: 0

### Features

- standings: engine v1.4.0, raw speaker totals with average and speeches (#15) by @merv1n34k
- cab: optional turnstile and form rate limits for public forms (#13) by @merv1n34k
- cab: club logo on the club page, directory and /r (#11) by @merv1n34k
- cab: batch select, copy links and remove on the session's people list (#8) by @merv1n34k
- cab: delete a session only while nobody signed up (#6) by @merv1n34k
- cab: form responses page per session with a csv download (#5) by @merv1n34k
- cab: the head sets the number of rooms by hand (#4) by @merv1n34k
- guest registration form editor, logic in core (#2) by @merv1n34k

### Fixes

- cab: refuse blank, invisible and over-long text in every form (#12) by @merv1n34k
- deps: bandit 1.13.1 for CVE-2026-105660 (#7) by @merv1n34k
- cab: demo and walkthrough scripts take MIX_ROOT; colocated css path (#1) by @merv1n34k

### Other

- chore: unified release flow, dev: targets, main as the release branch (#14) by @merv1n34k
- chore(engine): bump to 7320418, archived rooms no longer block removal (#10) by @merv1n34k
- chore(cab): translation files without line numbers, sorted by msgid (#9) by @merv1n34k
- test(cab): the walkthrough's guests give the required e-mail (#3) by @merv1n34k

### Contributors

- @merv1n34k: 15 commits
