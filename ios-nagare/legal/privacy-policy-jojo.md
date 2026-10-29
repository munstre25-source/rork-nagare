# Jojo — Privacy Policy

**Effective date: October 29, 2026**
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

## 4. Anonymous sync ID and backup

After onboarding, the app creates an **anonymous ID** on our backend (Supabase). There is no email, name, or password. The ID is kept in your iPhone's Keychain so your backup can come back after a reinstall. These are stored under that ID:

- **Saved words**: the word, reading, meanings, the sentence it came from, how often you met it, and its review stage. This lets your deck come back after a reinstall.
- **Speaking practice**: the line you practiced, the text speech recognition heard, and a **recognition match** percentage. The percentage compares two pieces of text. It is **not** a pronunciation score.
- **Your own videos**: YouTube links you submit, plus their processing status.

Only your anonymous ID can read your rows, enforced by row-level security on our database.

## 5. Your own videos (YouTube + Google Gemini)

When you paste a YouTube link, our server checks the public video details through the **YouTube Data API**. It then asks **Google Gemini** (through OpenRouter) to transcribe and translate the Japanese speech from that public YouTube URL. **We never download or store the video or its audio.** We store the resulting captions, readings, and translations so the lesson opens instantly. Videos always play through YouTube's official embedded player, under YouTube's Terms of Service and Google's Privacy Policy. If two learners submit the same video, the same captions are reused, but neither learner can see the other's requests.

## 6. Speaking practice audio

When you practice speaking, your microphone audio is turned into text by Apple's Speech framework. **Whenever your iPhone supports it, this happens entirely on the device.** On devices without on-device support, Apple processes the audio under Apple's privacy policy. We never receive, record, or store your audio, and the app writes no recording files.

## 7. Deleting your data

**Profile → Delete my data** removes everything on this iPhone. It also deletes your anonymous ID from our backend, which deletes your synced words, speaking practice, and video requests along with it. If you're offline, the deletion is retried the next time the app opens. Shared captions made from public videos are kept for other learners, but they are no longer linked to you.

## 8. What the app stores on your device

Your vocab deck, review history, streaks, goals, settings, and finished video lessons are stored on your device (SwiftData and app files). CloudKit sync is disabled. Your device is the source of truth, and the backup in section 4 only refills words that are missing.

## 9. Notifications

If you enable reminders, local notifications are scheduled on device. No notification tokens or device fingerprints are sent to us.

## 10. Data summary (App Store "privacy nutrition labels")

| Data | Purpose | Linked to you | Used for tracking |
|---|---|---|---|
| Device ID | Third-party advertising (Meta attribution, after ATT opt-in) | Yes | Yes |
| Device ID | Analytics | Yes | No |
| Product interaction | Third-party advertising (onboarding/feedback events, after ATT opt-in) | Yes | Yes |
| Product interaction | Analytics | Yes | No |
| User ID (anonymous RevenueCat ID and anonymous sync ID) | App functionality | Yes (anonymous sync ID) | No |
| User ID | Analytics | No | No |
| Purchase history | App functionality (subscription management) | No | No |
| Other user content (word/sentence text, saved words, speaking-practice text, submitted YouTube links) | App functionality (AI explanations, backup, video lessons) | Yes (to the anonymous sync ID) | No |

## 11. Children

Jojo is not directed at children under 13 and does not knowingly collect their data.

## 12. Changes

We update this policy when data practices change; the effective date above always reflects the current version. Questions or data requests: **support@socialreporthq.com**.
