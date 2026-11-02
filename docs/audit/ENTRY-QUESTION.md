# Entry-flow question

User feedback (verbatim): "how directly landing page and already ready it looks like ready made"
Meaning: opening http://localhost:5173 drops you straight into a dashboard already full of seeded pickups/devices.
It feels fake/pre-made, not like a product someone uses from the start.

Audience: Revivn recruiter (15-min screen-share), Director of Eng, Rails devs. Role: Product Engineer, Customer Platform.
Stack constraints: Rails 8.1 API backend must do the real work; React 19 + plain CSS; no new gems/npm packages;
no real auth (seeded current_customer); every line explainable in interview; build in ~half a day.

Candidate pieces (pick, combine, or propose better):
1. Landing/welcome page explaining the product (who it's for, the chain-of-custody flow) with "Enter customer portal".
2. Fake "Sign in as Acme Corp (demo account)" step (no real auth) so it feels like a real customer platform.
3. First-run empty state: start with zero pickups + onboarding ("Book your first pickup"), plus a
   "Load sample data" option backed by a Rails endpoint (e.g. POST /demo/reset with ?sample=true).
4. "Reset demo" control so each screen-share starts clean.
5. Guided demo steps / checklist overlay walking the viewer through book -> collect -> sanitize -> certificate.
6. Something else.

Answer: recommended combination, the exact first 30 seconds the recruiter sees, what to cut, max 12 lines.
