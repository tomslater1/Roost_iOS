# Roost — App Store Readiness Checklist

A living checklist covering everything needed to ship Roost, split by what's needed for **TestFlight Beta** vs the **Full App Store Release**. Work through beta first — most of it becomes the foundation for full release anyway.

---

## How to read this

- **Beta** = needed to get onto TestFlight (external testing)
- **Full** = needed before submitting for App Store review
- Items marked ⚠️ are easy to overlook and commonly cause rejection

---

## 1. Apple Developer Account & Certificates

| Item | Beta | Full |
|---|---|---|
| Apple Developer Program membership ($99/year, paid) | ✅ | ✅ |
| Bundle ID registered (`com.yourname.roost` or similar) | ✅ | ✅ |
| Distribution certificate created in Xcode / Apple Developer portal | ✅ | ✅ |
| App Store provisioning profile created | ✅ | ✅ |
| App record created in App Store Connect | ✅ | ✅ |
| Version number set (e.g. `1.0.0`) and build number set (e.g. `1`) | ✅ | ✅ |
| iOS deployment target confirmed (iOS 17+) | ✅ | ✅ |
| Push notification certificate (if Roost sends any push notifications) | ✅ | ✅ |

---

## 2. App Icons & Launch Screen

| Item | Beta | Full |
|---|---|---|
| App icon 1024×1024 PNG, no alpha channel, no rounded corners ⚠️ | ✅ | ✅ |
| All `AppIcon` sizes populated in `Assets.xcassets` | ✅ | ✅ |
| Launch screen polished (not a blank white screen) | ✅ | ✅ |
| Launch screen matches app's warm cream background (not jarring) | — | ✅ |

> You already have `AppIcon~ios-marketing.png` — just confirm it's exactly 1024×1024 and has no alpha channel (Apple rejects icons with transparency).

---

## 3. Legal Documents

This is one of the most commonly skipped areas for first-time apps. Because Roost handles **financial data and couples' shared account data**, the bar here is higher than a simple game.

| Item | Beta | Full |
|---|---|---|
| Privacy Policy hosted at a public URL ⚠️ | ✅ | ✅ |
| Privacy Policy covers data Roost collects (finances, household data, account info) | ✅ | ✅ |
| Terms of Service / EULA | — | ✅ |
| Data deletion policy (what happens if a user deletes their account) | — | ✅ |
| GDPR compliance section (if you have any EU users) | — | ✅ |
| CCPA compliance section (if you have any California users) | — | ✅ |
| Clear disclosure of Supabase as a third-party data processor | — | ✅ |
| Statement about financial data not being sold to third parties | — | ✅ |

> **Quick note on Privacy Policy for beta:** Apple requires a privacy policy URL even for external TestFlight. A simple one is fine for beta — it just needs to exist and be accessible. You can refine it before full release. Free tools like Termly or iubenda can generate a starter version quickly.

---

## 4. App Store Connect Metadata (Listing Copy)

This is your storefront. Everything here directly affects downloads.

| Item | Beta | Full |
|---|---|---|
| App name (max 30 characters) — "Roost" | ✅ | ✅ |
| TestFlight description (what testers should focus on) | ✅ | — |
| Subtitle (max 30 characters) — e.g. "Home life, together" | — | ✅ |
| Full description (max 4,000 characters) | — | ✅ |
| Promotional text (max 170 characters, can update without resubmission) | — | ✅ |
| Keywords (max 100 characters total) ⚠️ | — | ✅ |
| Primary category (e.g. Lifestyle or Productivity) | — | ✅ |
| Secondary category (optional but worth filling) | — | ✅ |
| Age rating questionnaire completed | — | ✅ |
| Support URL (can be a simple email link or support page) | — | ✅ |
| Marketing URL (landing page for the app) | — | ✅ |
| Copyright string (e.g. "© 2026 Tom Slater") | — | ✅ |
| "What's New" text for future updates | — | ✅ |

> **On keywords:** Apple's algorithm is heavily influenced by keywords. Spend real time on this — research what phrases couples search for (household, shared finances, chores, home budget, etc.). You only get 100 characters and no commas in the keyword field.

> **On name/trademark:** Before full release, do a quick trademark search for "Roost" in your market. There are other apps/companies using it.

---

## 5. Screenshots & Visual Assets

Screenshots are your single biggest conversion lever on the App Store. First-time developers almost always underinvest here.

| Item | Beta | Full |
|---|---|---|
| App icon confirmed correct (see section 2) | ✅ | ✅ |
| Screenshots not required for TestFlight | — | — |
| Screenshots for 6.7" display (iPhone 15 Pro Max) — **required** ⚠️ | — | ✅ |
| Screenshots for 6.5" display (iPhone 14 Plus / 11 Pro Max) | — | ✅ |
| Screenshots for 5.5" display (iPhone 8 Plus) — sometimes optional if 6.7" is present | — | ✅ |
| Screenshots show real app UI (no placeholder or lorem ipsum) | — | ✅ |
| Screenshots tell a story across the 3–5 images (not just random screens) | — | ✅ |
| Designed screenshots with captions/context overlaid ⚠️ | — | ✅ |
| App preview video (15–30 seconds, optional but strongly recommended) | — | ✅ |
| iPad screenshots (only if your app supports iPad) | — | ✅ |

> **On designed screenshots:** Raw screenshots rarely convert well. The best-performing App Store pages layer context — short captions like "Split expenses effortlessly" — on top of the UI. Given Roost's design quality, this is a real opportunity to stand out. Tools like Rottenwood, AppLaunchpad, or even Figma work well for this.

---

## 6. App Privacy Nutrition Label

Apple requires you to self-report your data practices before going live. This shows up as the "App Privacy" section on every App Store page.

| Item | Beta | Full |
|---|---|---|
| Data types declared (account info, financial info, usage data, etc.) | — | ✅ |
| Data linked to user identity declared ⚠️ | — | ✅ |
| Third-party SDK data practices reviewed (Supabase, any analytics) | — | ✅ |
| No undisclosed tracking | — | ✅ |

> Be honest and thorough here. Apple cross-checks this against your app's actual behaviour. Because Roost collects financial data and links it to user accounts, you'll likely need to declare "Financial Info" and "Contact Info" at a minimum.

---

## 7. Account Creation & Deletion (Apple Requirement)

Since June 2023, Apple **requires** that any app with account creation also provides in-app account deletion. This is a hard rule — missing it will get you rejected.

| Item | Beta | Full |
|---|---|---|
| Users can create an account in-app | ✅ | ✅ |
| Users can delete their account from within the app ⚠️ | ✅ | ✅ |
| Account deletion actually purges data from Supabase (not just soft-delete) ⚠️ | ✅ | ✅ |
| Deletion confirmation flow (not accidental) | ✅ | ✅ |
| Couples data handling on deletion (what happens to shared data?) | ✅ | ✅ |

---

## 8. App Review Practicalities

Apple's review team needs to be able to actually use your app. This trips up couples/household apps especially.

| Item | Beta | Full |
|---|---|---|
| Demo / test account credentials provided in review notes ⚠️ | ✅ | ✅ |
| Reviewer can use core features without needing a partner ⚠️ | ✅ | ✅ |
| No features gated behind invite-only flows without a fallback for reviewers | ✅ | ✅ |
| App doesn't crash on cold launch | ✅ | ✅ |
| All listed features are actually functional (not grayed out or placeholder) | — | ✅ |
| Review notes explain the app's purpose and any non-obvious flows | ✅ | ✅ |
| Financial features comply with Apple's financial services guidelines | ✅ | ✅ |

> The couples pairing flow is your biggest review risk. If a reviewer can't get past an "invite your partner" screen, they'll reject the app. Make sure there's a solo mode or a way to test the full app alone.

---

## 9. Technical Polish

| Item | Beta | Full |
|---|---|---|
| No crashes on core user flows | ✅ | ✅ |
| Secrets not hardcoded in source (Secrets.xcconfig excluded from git) ⚠️ | ✅ | ✅ |
| App handles no internet connection gracefully | ✅ | ✅ |
| App handles Supabase errors gracefully (not blank screens or crashes) | ✅ | ✅ |
| All entitlements declared (Keychain, Push, etc.) | ✅ | ✅ |
| No private/undocumented Apple API usage | ✅ | ✅ |
| App doesn't request unnecessary permissions | ✅ | ✅ |
| All permission request strings are honest and clear (e.g. Face ID reason string) | ✅ | ✅ |
| Reduce Motion preference respected in animations | — | ✅ |
| Dynamic Type support (text scales with accessibility settings) | — | ✅ |
| VoiceOver labels on core interactive elements | — | ✅ |
| Basic crash reporting set up (Crashlytics / Sentry) | ✅ | ✅ |

---

## 10. Monetisation (decide before beta, implement before full release)

| Item | Beta | Full |
|---|---|---|
| Monetisation model decided (free / freemium / subscription / one-time) | ✅ | ✅ |
| In-App Purchase products created in App Store Connect (if applicable) | — | ✅ |
| StoreKit implementation tested on real device (not simulator) | — | ✅ |
| Restore purchases button present (Apple requires this) ⚠️ | — | ✅ |
| Subscription management link present (Settings → Manage Subscription) | — | ✅ |
| Pricing reviewed across all target markets | — | ✅ |

---

## 11. Promotional Materials (not needed for beta)

| Item | Beta | Full |
|---|---|---|
| Landing page / marketing website with App Store link | — | ✅ |
| Designed App Store screenshots with captions (see section 5) | — | ✅ |
| App preview video (15–30 sec walkthrough) | — | ✅ |
| Social media announcement assets | — | ✅ |
| Press kit (app icon, screenshots, description) if planning any PR | — | ✅ |
| Launch strategy decided (soft launch, waitlist, Product Hunt, etc.) | — | ✅ |

---

## 12. Things Specific to Roost

These aren't generic checklist items — they come from what I can see about the app specifically.

| Item | Beta | Full |
|---|---|---|
| **Couples pairing reviewed by Apple** — the invite/join flow needs a way for a solo reviewer to test the app fully | ✅ | ✅ |
| **Financial data handling** — because Roost tracks spending, the App Privacy label and Privacy Policy both need to clearly cover financial info | ✅ | ✅ |
| **Banking-grade security features** — Face ID / PIN use requires a clear usage description string and should be explained in review notes | ✅ | ✅ |
| **PIN migration** — the PBKDF2/Keychain migration from UserDefaults should be fully tested on a fresh install and an upgrade from an old build | ✅ | ✅ |
| **Name trademark check** — "Roost" is used by other companies; worth a quick search before committing to it on the App Store | — | ✅ |
| **Category choice** — "Lifestyle" or "Productivity" are the likely homes; "Finance" is possible given the Money tab but may attract more scrutiny | — | ✅ |
| **Shared data on partner removal** — what happens to shared expenses, chores, shopping lists if a couple splits or one user deletes their account? This needs a defined behaviour and ideally a clear in-app explanation | — | ✅ |

---

## Summary: What to do first

If you want to get onto TestFlight as fast as possible, focus on these in order:

1. Apple Developer account active and bundle ID registered
2. App icon 1024×1024 with no alpha (verify your existing one)
3. Privacy Policy live at a public URL
4. Account deletion flow working in-app
5. Demo credentials for review team ready
6. Couples pairing reviewable solo (or with two test accounts you control)
7. No crashes on core flows
8. Build uploaded and passing Apple's processing

Everything else can follow in the lead-up to full release.

---

*Last updated: April 2026*
