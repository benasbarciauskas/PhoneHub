# Security Baseline

Every Ruflo app must hold the line on these. Items are grouped; treat all as required
unless genuinely N/A for the app's architecture. This file is installed by the
Ruflo Git Standard and should be reviewed per repo.

## Secrets & exposure
1. No exposed database credentials.
2. No public `.env` files (gitignored; never committed — enforced by the pre-commit hook).
3. No hardcoded API keys/tokens — load from env / keychain.
11. Build/CI logs must not print secrets.
13. Repos stay private; no secrets in commit history (rotate immediately if leaked).
14. No secrets in frontend JavaScript bundles.
35. Logs must not contain tokens, emails, passwords, or private user data.
36. No source maps shipped to production.
26. JWT signing secrets are strong, unique per app, never reused or committed.

## AuthN / AuthZ / multi-tenant
4. Strong authentication on every protected surface.
5. Authorization checks on every protected action (not just authentication).
6/33. No IDOR — users can never reach another user's data; never trust user-supplied IDs.
34. Endpoints must not trust user-controlled role/permission claims.
9/45. Admin routes & internal dashboards are protected and not publicly reachable.
49. Strong tenant isolation in multi-user apps.

## Input handling & injection
16. Validate & sanitize all input at the boundary.
17/18. Parameterized queries — no SQL/NoSQL injection.
19. Escape output — no XSS.
20. CSRF protection on state-changing requests.
21/22. Safe file uploads; no path traversal.
23. No SSRF — validate/allowlist outbound URLs from user input.
39/40. Treat AI input as untrusted (prompt injection); AI tools/actions enforce the same authz as the user.

## Sessions, cookies, transport, headers
24/25. Robust password-reset & session management.
27. CORS is locked down (explicit origins, not `*` with credentials).
46. Security headers set (CSP, HSTS, X-Content-Type-Options, etc.).
47. Cookies are `HttpOnly` + `Secure` + `SameSite`.
48. Sensitive data encrypted at rest and in transit.

## Platform / infra config
7/41. Least-privilege DB perms; no open read/write.
8. Firebase/Supabase/S3 buckets locked down (no public read/write).
10. No debug pages in production.
12. No verbose error/stack traces to users.
28. Rate limits on login, signup, APIs, and AI endpoints.
29. No public test/staging environments.
30. No default credentials.
31. Webhook endpoints verify signatures.
32. Payment/subscription checks enforced server-side (never frontend-only).
15. Never rely on client-side-only security checks.

## Dependencies, ops, process
37/38. No known-vulnerable or outdated dependencies (`npm audit` in CI).
42/43. Audit logs + monitoring/alerting for sensitive actions.
44. Backup & restore plan for real data.
50. Never merge generated code without review.

---
_Pre-commit secret scanning + `npm audit` in CI cover items 2, 3, 14, 37, 38 automatically.
The rest are reviewed per repo — see `/gsd-secure-phase` or the security-auditor agent for a deep audit._
