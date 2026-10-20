# Jojo — Privacy Policy

**Effective date: October 20, 2026**
Jojo ("the app") is operated by SocialReport HQ ("we", "us"). Contact: **support@socialreporthq.com**.

We do **not** create user accounts. Everything below describes data the app and its service providers handle; there is no profile, email, or sign-up required to use the app.

## 1. Tracking and advertising (Meta SDK)

The app uses the Meta (Facebook) SDK for **ad attribution and measurement** — it tells us which ads brought people to the app so we spend our marketing budget sensibly.

- **Device identifiers** (such as the advertiser ID and Meta's anonymous ID) and **app events** (onboarding steps, feedback actions) are collected for ad attribution and measurement.
- The advertiser ID is only collected and used for tracking **if you allow tracking** when iOS shows the "Allow Jojo to track your activity across other companies' apps and websites?" prompt. If you decline, attribution falls back to privacy-preserving, non-tracking methods.
- You can change your choice anytime in **Settings → Privacy → Tracking**.
- The SDK contacts Meta's servers (`ep1.facebook.com`) for attribution.

## 2. Subscriptions (RevenueCat)

Purchases are managed by RevenueCat. It stores an **anonymous app user ID** (generated on device, no account needed) plus your **purchase history** (e.g., active subscription, trial status) so the app can unlock features, work across reinstalls when you tap *Restore Purchases*, and sync entitlements. RevenueCat acts as our processor; see revenuecat.com/privacy.

## 3. AI word explanations (Google Gemini)

When you tap a word that isn't already answered in the app, the **selected word and sentence text** is sent to our own server function, which asks **Google Gemini** to produce the explanation. Results are cached on our server **under an anonymous key** — no account, name, or device identity is attached. The text is used only to generate and cache your explanation.

## 4. What the app stores on your device

Your vocab deck, review history, streaks, goals, and settings are stored locally on your device (SwiftData). CloudKit sync is disabled. Removing the app removes that data.

## 5. Notifications

If you enable reminders, local notifications are scheduled on device. No notification tokens or device fingerprints are sent to us.

## 6. Data summary (App Store "privacy nutrition labels")

| Data | Purpose | Linked to you | Used for tracking |
|---|---|---|---|
| Device ID | Third-party advertising (Meta attribution, after ATT opt-in) | Yes | Yes |
| Device ID | Analytics | Yes | No |
| Product interaction | Third-party advertising (onboarding/feedback events, after ATT opt-in) | Yes | Yes |
| Product interaction | Analytics | Yes | No |
| User ID (anonymous RevenueCat ID) | App functionality | No | No |
| User ID | Analytics | No | No |
| Purchase history | App functionality (subscription management) | No | No |
| Other user content (word/sentence text) | App functionality (AI explanations) | No | No |

## 7. Children

Jojo is not directed at children under 13 and does not knowingly collect their data.

## 8. Changes

We update this policy when data practices change; the effective date above always reflects the current version. Questions or data requests: **support@socialreporthq.com**.
