# LianLeMe (练了么) · Privacy Policy

> **Status: DRAFT — not yet reviewed by counsel; do not use for store submission as-is.**
>
> This is the English translation of `docs/privacy-policy.md`. **In case of any discrepancy,
> the Chinese version prevails.**
>
> Every statement below was **verified against the source code**, not copied from a template
> (see Appendix B for how to check it yourself).
>
> **Two things remain before submission:**
> 1. ⬜ Legal review — workout data is **sensitive personal information** under China's PIPL
> 2. ⬜ Replace the "Effective date" with the actual first release date
>
> | | |
> |---|---|
> | Operator | **Elliot.LI** (individual developer) |
> | Contact | **https://github.com/sdknwdtvpv-sys/sport/issues** |
> | Effective date | **date of first release** (currently: `not released` — must be filled in before publishing) |

---

## 1. In one sentence

**LianLeMe is an offline-first workout logging tool. Your training data stays on your own phone.
There is no sign-up, no phone number, no location, no contacts. The only network activity is
anonymous usage statistics when the "Help improve the product" switch is on — and you can turn
that off at any time.**

---

## 2. What we collect

### 2.1 Stored only on your device, never uploaded

| Data | Content | Purpose |
|---|---|---|
| Workout records | Exercise, weight, reps, set index, warm-up flag, completion time | Log your training; compute volume and progress |
| Workout sessions | Start/end time, total sets, total volume | Workout summary screen |
| Preferences | Progression-suggestion switch, unit preference, "Help improve the product" switch | Remember your choices |

This data lives in the app's private local database (SQLite, managed by drift) and
**never leaves the device**.

### 2.2 Collected only when "Help improve the product" is ON

This is a **switch that is on by default and can be turned off at any time**
(Profile → "Help improve the product"). It produces exactly **9 event types** with a
**fixed, limited** set of fields (the full list lives in `docs/privacy-facts.json` and is
checked against the code by `tool/privacy-audit.mjs`):

| Event | When | Fields |
|---|---|---|
| `set_logged` | When a set is logged | `workout_id`, `exercise_id`, `set_index`, `weight_kg`, `reps`, `distance_m`, `set_type`, `rpe`, `tap_count`, `tap_kinds`, `entry`, `is_offline` |
| `set_undone` | When a set is undone | `set_index`, `method`, `seconds_after_log` |
| `app_open` | Cold start finished | `is_first_open`, `ms_since_launch`, `entry` |
| `workout_started` | Entering the workout screen | `source`, `exercise_count`, `ms_since_launch` |
| `workout_finished` | Workout finished | `duration_sec`, `total_sets`, `total_volume_kg`, `exercise_count`, `ms_since_launch` |
| `rest_started` | Rest timer starts | `exercise_id`, `planned_sec`, `auto` |
| `rest_completed` | Rest timer finishes | `exercise_id`, `planned_sec` |
| `rest_skipped` | Rest skipped manually | `exercise_id`, `planned_sec` |
| `seed_import_failed` | Exercise-library refresh failed | `error` (error type only, no content) |

**Every event also carries these 7 common fields:**

| Field | What it is |
|---|---|
| `device_id` | **Locally generated anonymous identifier** (32 hex chars). Unrelated to any account, contains no device information. Cleared by "Delete all data" |
| `session_id` | Random identifier for one usage session; a new one after 30 minutes of inactivity |
| `user_id` | **Always null** — there is no account system. Guests are counted too, otherwise the "did new users start training" metric cannot be computed |
| `app_version` | Version string (used to compare "taps per set" across versions) |
| `platform` | `android` / `ios` |
| `is_offline` | Whether the device was offline when the event happened |
| `schema_version` | Event schema version, append-only |

A few clarifications:

- `workout_id` / `exercise_id` / `device_id` / `session_id` are **locally generated random
  identifiers**. They are not your identity and contain no phone number, IMEI or advertising ID.
- We can see "which exercise, what weight, how many sets" — because that is the core metric the
  product needs to validate (`tap_count` measures "how many taps it takes to log a set").
  **This is health-related information and we treat it as sensitive personal information.**
- `entry` records whether the set was logged via the big button or via long-press editing.

### 2.3 What we do NOT collect

- ❌ Name, phone number, email, government ID — **there is no account system**
- ❌ Location
- ❌ Contacts, photos, camera, microphone
- ❌ Advertising identifiers (no ad SDKs)
- ❌ Clipboard contents ("Export" **writes** to your clipboard for you; we never read it)
- ❌ **Body-weight and other body-metric values** — only booleans such as "weight recorded" /
  "note present" are reported; the numbers never leave the device
- ❌ **Free text** such as workout notes or custom exercise names

---

## 3. Where the data lives and who receives it

### 3.1 Current state — the app does not upload anything

**The current version does not send any of your data to any server.** This is not a promise;
it is a fact of the code:

- The upload endpoint is configured **at build time**: with no endpoint the analytics channel is
  `_NullTransport`, which **always fails** — events only accumulate
  in the on-device outbox.
- The workout sync channel is `InMemorySyncQueue`: memory only, no network, gone when the app closes.

In other words, **even we cannot access your data right now.** We state this plainly because
describing a future feature as already shipped would be dishonest — and so would pretending
"nothing happens" is a feature.

### 3.2 After a real endpoint is connected

In a future version, when the switch above is ON, the events in 2.2 will be sent over HTTPS to a
receiver we operate. This policy will be updated with a new version and effective date, and the
app will notify you. **Whenever the switch is off, not a single event is sent.**

We **never sell, rent, or share** your personal information with third parties. No third-party
advertising. No data brokers.

---

## 4. Permissions

The app declares two permissions; the second **only takes effect on old systems**:

| Permission | Why | Applies to |
|---|---|---|
| `android.permission.INTERNET` | Solely for the anonymous usage statistics in 2.2 (when the switch is ON) | All versions |
| `android.permission.WRITE_EXTERNAL_STORAGE` | Saving the "share card" image to the system gallery | **Android 9 and below only** (declared with `maxSdkVersion="29"`) |

Three notes on the second one:

- **Android 10+ does not need it at all** — modern Android writes to the gallery via
  MediaStore with no permission. Because we declare it with `android:maxSdkVersion="29"`,
  **users on newer systems never see it in the permission list.**
- It only grants image writes, and is used only when you tap "Save to gallery".
- The share card is **rendered on your device**: the image is drawn directly from the UI into
  a PNG and **is never uploaded to our servers**. Tapping "Share" hands the image to the
  system share sheet; which app you then pick (WeChat, Photos, …) is your choice, and that
  step is governed by that app's privacy policy.

Beyond these, we request **no** location, contacts, camera, microphone, calendar, or
background permissions.

> Implementation note: the Flutter template only adds INTERNET to the debug/profile variants
> (for hot reload), so the release build originally had no such permission. We declare it in
> `main` so all three variants behave identically — otherwise, once a real endpoint is wired,
> release builds would **fail silently** with no error.

---

## 5. Your rights and controls

| Right | How |
|---|---|
| **Turn off usage statistics** | Profile → "Help improve the product". Takes effect immediately; no feature is affected |
| **Export all your data** | Profile → "Export all records" — generates a CSV copied to your clipboard |
| **Delete all data** | Profile → "Delete all data". After a confirmation prompt, local records and settings are wiped immediately |
| **Uninstall to delete** | Uninstalling the app removes the local database |

What deletion covers, to avoid misunderstanding:

- **Deleted**: all workout and set records, preferences (including all switches), **and any
  analytics events not yet uploaded**, and the anonymous analytics identifiers
  (`device_id` / session id / first-open timestamp) — with the honest consequence that this device
  then counts as a new device in aggregate statistics
- **Not deleted**: the built-in exercise catalog (351 exercises) — that is product content and
  contains nothing about you
- It is a **hard delete**, not a flag. Deletion cannot be undone, and we hold no backup that
  could restore it.

---

## 6. Retention

- On-device data: kept until you delete it (which is what a workout log should do).
- Pending outbox events: size-capped; over the cap, lower-priority events are dropped first
  (P0 workout data is retained preferentially).
- Server-side: **no server-side data exists today.**

---

## 7. Minors

This product is not directed at children under 14, and we do not knowingly collect their personal
information. If you are a guardian and believe we hold such information, please contact us via the
link above.

---

## 8. Changes to this policy

When this policy changes we will announce it in-app and in the release notes, and update the
effective date at the top. For material changes (for example, beginning real uploads) we will ask
for your consent separately.

---

## Appendix A: where these statements come from

| Statement | Source |
|---|---|
| The 9 analytics events and their fields | `app/lib/features/workout/workout_controller.dart` (`track(...)` call sites) |
| Switch defaults to ON and is persisted | `app/lib/data/db.dart` (`analyticsEnabled`, default `true`), `app/lib/data/profile_repository.dart` |
| When off, nothing is recorded | `app/lib/analytics/analytics.dart` (`NoopAnalytics`, and `if (!enabled) return;`) |
| Nothing is uploaded today | `app/lib/main.dart` (`_NullTransport`), `app/lib/data/sync_queue.dart` (`InMemorySyncQueue`) |
| No requests during a workout | `app/lib/analytics/flusher.dart` (`suspend()` / `resume()`), guarded by tests |
| Only the INTERNET permission | `app/android/app/src/main/AndroidManifest.xml` |
| Right to deletion is available | `app/lib/features/profile/profile_screen.dart` (`_deleteAll`), `app/lib/data/local_store.dart` (`deleteAllUserData`) |
| Deletion includes pending events | `app/lib/data/drift_local_store.dart` (deletes `analyticsOutbox` in the same transaction) |
| No account system | No login/sign-up code anywhere; `app/lib/data/` contains only local storage |

## Appendix B: verify it yourself

You do not have to take this document on faith:

```bash
# 1. Permissions: the merged release manifest should list only INTERNET
grep uses-permission app/build/app/intermediates/merged_manifest/release/*/AndroidManifest.xml

# 2. What the analytics layer actually sends
grep -rn "track('" app/lib/

# 3. Whether anything is uploaded today (should be the always-failing _NullTransport)
grep -n "_NullTransport" app/lib/main.dart
```
