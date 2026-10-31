# Changelog

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
