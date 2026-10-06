# LianLeMe (练了么) · Privacy Policy

<!--
Maintainer note (never appears in generated artifacts — HTML comments are stripped, and the
in-app copy drops them too):

This Markdown is the single source for two generated artifacts:
  * store-assets/privacy/en.html  — the page hosted publicly and given to the stores
  * (the in-app copy is generated from the Chinese original)

Paragraphs wrapped in the pair of HTML comment markers named with the Chinese word for
"internal" exist only in this source file: they are developer-facing (status, TODOs, file
paths, verification commands) and would look wrong on a public page or inside the app.
-->

<!-- 内部 -->
> **Status: DRAFT — not yet reviewed by counsel; do not use for store submission as-is.**
>
> This is the English translation of `docs/privacy-policy.md`. **In case of any discrepancy,
> the Chinese version prevails.**
>
> **Two things remain before submission:**
> 1. ⬜ Legal review — workout data is **sensitive personal information** under China's PIPL
> 2. ⬜ Replace the "Effective date" with the actual first release date
>
<!-- /内部 -->

| | |
|---|---|
| App | **LianLeMe (练了么)**, Android package `com.sdknwdtvpv.lianleme` |
| Operator | **Elliot.LI** (individual developer) |
| Contact | **https://github.com/sdknwdtvpv-sys/sport/issues** |
| Effective date | **the date of first release** |

<!-- These three are **required public information** (who processes your data, how to reach us,
from which date this applies), so they sit outside the internal block. -->
<!-- (This note itself must stay inside a comment — the first version was a blockquote and
shipped with the policy.) -->

---

## 1. In one sentence

**LianLeMe is an offline-first workout logging tool. Your training data stays on your own phone.
There is no sign-up, no phone number, no location, no contacts. The only network activity is
anonymous usage statistics — and that switch is **off by default**: you have to
**turn it on yourself**, and you can turn it off again at any time.**

---

## 2. What we collect

### 2.1 Stored only on your device, never uploaded

| Data | Content | Purpose |
|---|---|---|
| Workout records | Exercise, weight, reps, set index, warm-up flag, completion time | Log your training; compute volume and progress |
| Workout sessions | Start/end time, total sets, total volume | Workout summary screen |
| **Body metrics** | **Body weight (kg; displayed in the unit you pick), body fat percentage, waist (cm), muscle mass (kg), height (cm), a note** | So you can see long-term change |
| Preferences | Progression-suggestion switch, unit preference, "Help improve the product" switch, **pinned exercises** | Remember your choices |

This data lives in the app's private local database (SQLite, managed by drift) and
**never leaves the device** — the one possible exception is **cloud backup that you enable
yourself**: that copy is encrypted on your phone before it leaves, and only ciphertext leaves
(see 3.1).

> **Body weight is sensitive personal information, and we ask for your separate consent.**
> Under Article 29 of China's Personal Information Protection Law, processing sensitive
> personal information in the health category requires **separate consent** — the general
> "agree to the privacy policy" on first launch **is not** that consent. So the **first time
> you open the Body metrics screen** we show a dedicated explanation (kept on this device by
> default; uploaded as ciphertext only if you yourself turn on cloud backup; editable and
> deletable at any time) and only start recording after
> you agree; choosing "not now" means we do not open that screen and collect nothing.
> To be explicit about purpose: it is used **only so you can see your own long-term change** —
> never for advertising or any other purpose (App Store Guideline 5.1.3 likewise forbids
> using health data for advertising or sale).
>
> **Body fat percentage, waist, muscle mass and height sit behind the same gate** (since
> v1.52): they are body metrics just like weight, so they share that one separate consent
> instead of prompting again for every new field — but none of those numbers is
> **included in analytics**, and we never collect them on our own. Height is
> used solely to compute BMI (weight ÷ height²); with no height entered we show no BMI.
>
> ⚠️ **Since 2026-10-05 body metrics travel with the cloud backup you enable yourself**
> (they were not in the backup before that): when you change phones, body weight, body fat,
> waist, muscle mass and height should come back too — otherwise users reasonably conclude
> "my data did not all come back". Their destination is exactly the same as your workout
> records: **only if you turn on cloud backup** under Me → Data & backup → Cloud backup does
> that copy get **end-to-end encrypted** and uploaded (the server holds ciphertext only and
> cannot read a single value). Cloud backup is **off by default**, so nothing is uploaded
> unless you turn it on. **After you withdraw this consent, no later backup contains those
> values** (the rule lives in code and is pinned by tests).
>
> **You can withdraw that consent at any time** (PIPL Article 15). The entry sits at the
> bottom of the Body metrics screen — "Withdraw my consent". After withdrawal we stop
> collecting new weight, body fat, waist, muscle mass and height readings immediately and
> that screen asks for your consent again
> the next time you open it; **records you already saved are not deleted automatically**
> (withdrawing consent and deleting data are two different things — delete data yourself
> under "All data").

### 2.2 Collected only when "Help improve the product" is ON

This is a **switch that is off by default**: nothing below is produced unless you
**turn it on yourself** (Profile → Privacy & About → "Help improve the product");
once on, you can turn it off again at any time, effective immediately. It produces exactly **22 event types** with a
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
| `onboarding_step` | Each onboarding step (advanced or skipped) | `step_index`, `skipped` |
| `exercise_added` | An exercise is picked or created | `exercise_id`, `add_method` |
| `set_edited` | The stepper was confirmed with a **real** change | `field`, `from`, `to`, `suggestion_id` |
| `suggestion_shown` | A set was logged while a suggestion was on screen | `suggestion_id`, `exercise_id`, `reason_code`, `suggested_weight_kg`, `suggested_reps` |
| `suggestion_accepted` | The logged value matched the suggestion | `suggestion_id`, `reason_code` |
| `suggestion_modified` | The logged value differed from the suggestion | `suggestion_id`, `reason_code`, `delta_weight_kg`, `delta_reps`, `direction` |
| `pr_achieved` | A personal record was broken | `exercise_id`, `pr_type`, `value`, `prev_value` |
| `share_card_created` | A share card was saved or shared | `channel` |
| `body_metric_logged` | A body-metric entry was saved | `has_weight`, `has_note` — **only whether a value was entered; the value itself never leaves the device** |
| `cloud_backup_done` | Cloud backup **uploaded successfully** | `ciphertext_bytes`, `has_body` — **only how large the ciphertext is and whether body data was included**; never the content, never a file name |
| `cloud_backup_failed` | Cloud backup upload failed (or account creation / binding / entering a recovery code failed) | no fields — **only the failure itself** (the error text could contain a server address, so it is not sent) |
| `cloud_restore_done` | Restore from the cloud **succeeded** | `workouts`, `body_synced` — only how many records came back |
| `cloud_restore_failed` | Restore from the cloud failed | no fields — the failure itself only |

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
- ❌ **Body-weight and other body-metric values** — analytics reports only booleans such as
  "weight recorded" / "note present"; **the numbers never enter analytics and we never read
  them**. The only path off the device is the cloud backup you enable yourself (see 2.1 and 3.3)
- ❌ **Free text** such as workout notes or custom exercise names

---

## 3. Where the data lives and who receives it

### 3.1 Two things can reach the network — both off by default

**Nothing is uploaded unless you turn a switch on yourself** — there are exactly two such
switches, and both are **off by default**:

- **Anonymous usage statistics** (off by default). When you turn it on, the events in 2.2 are sent
  over HTTPS to a receiver we operate. **When the switch is off, not a single event is sent** —
  and you can verify that yourself: install the app, watch it with any packet capture tool for a
  full day, and with the switch off you should see **zero** requests to us (this is exactly how we
  verify it during development).
  ⚠️ **The first release that reports anything does not send events accumulated by earlier
  versions**: that backlog is cleared the first time a reporting build starts ("whoever recorded
  it, sends it"). Events you recorded in an older version are **not** uploaded retroactively.
- **Cloud backup** (**off by default**; you turn it on in Profile → Data & backup → Cloud backup).
  Once on, **your workout records and body metrics** (weight / body fat / waist / muscle mass /
  height) are **end-to-end encrypted** and stored on a server — so you can
  get them back on a new phone, or if your phone is lost. **The server only ever receives
  ciphertext**: encryption happens on your phone, and we cannot read a single field;
  the **recovery code** is the only key and the server does not hold it — so **if you lose the
  recovery code, it is gone**. The exact contents of a backup are listed in 3.3.
- **Deleting all data will ask whether to delete the cloud backup as well** (the default is to
  delete both). The order is deliberate: the cloud copy is deleted **first**, and if that fails the
  whole operation stops. We would rather have you retry than leave you with local data gone, a
  cloud copy still there, and no recovery code left to open it.
- Your workout records **themselves** still live only on this device; apart from the cloud-backup
  ciphertext you chose to enable, they go nowhere.

### 3.2 Where the two switches draw the line

- **Statistics switch**: off — not a single event is sent; on — what leaves is the 22 event types
  in 2.2 plus the 7 common fields in 2.3, with no free text and no body-weight values.
- **Cloud-backup switch**: off — **no data leaves the device at all**; on — what leaves is
  **ciphertext** of the contents listed in 3.3.
- Both switches can be turned off **at any time**: turning statistics off stops the queue from
  sending; cloud backup can be closed in Data & backup (the cloud copy stays) or closed with
  account deletion (the cloud copy is deleted).
- We **never sell, rent, or share** your personal information with third parties. No third-party
  advertising. No data brokers.

### 3.3 What a cloud backup actually contains

Only **this** leaves the device as ciphertext once you enable cloud backup — here is its
entire content, with nothing "else we did not mention":

| Content | What it is |
|---|---|
| Workout records | Every workout: exercise id, weight (always kg), reps, set index, warm-up flag, RPE, distance, completion time |
| Exercise name table | Exercise id → Chinese name. **Used only to display names after a restore** (it never overwrites a name you changed yourself) |
| Pinned exercises | The exercises you pinned, in your order (in backups since 2026-10-04) |
| **Body metrics** | Daily body weight, body fat percentage, waist, muscle mass and note, plus height (in backups since 2026-10-05). ⚠️ **Included only while you still hold the separate consent in 2.1**; after you withdraw it, no later backup contains them |
| The backup's own bookkeeping | Export time, format version, weight-unit marker (`kg`) |

**Not included**: routine templates, settings such as units / rest duration / switches,
the anonymous analytics events, and your **recovery code itself** (it exists only on your
device — the server does not have it, so losing it means losing it).

Two points to be explicit about:

* **The server only ever has ciphertext**: encryption happens on your phone; not a single
  field is readable on our side;
* **Restoring only ever adds**: restoring fills in or overwrites the entry for the *same day* —
  it **never deletes** the readings you recorded yourself on the new phone.

---

## 3.5 Third-party dependencies (SDK list)

The following are our **direct dependencies** — not services we call, but libraries distributed
with the app. Chinese app stores require third-party SDKs to be listed
centrally with their name, function, and how they handle personal information, so here they are:

| Name | Version | Function | Does it collect or upload anything? | License | Link |
|---|---|---|---|---|---|
| `drift` | 2.35.0 | Local database (a SQLite wrapper): workout records and settings live here | **No.** Pure local reads and writes, no network code | MIT | [pub.dev](https://pub.dev/packages/drift) |
| `drift_flutter` | 0.3.1 | Provides the platform-specific storage path for that database | **No** | MIT | [pub.dev](https://pub.dev/packages/drift_flutter) |
| `sqlite3` | 3.6.0 | The actual SQLite engine (prebuilt binary per platform) | **No.** It is the database itself | MIT | [pub.dev](https://pub.dev/packages/sqlite3) |
| `share_plus` | 13.3.0 | Hands a share card or backup file to the **system** share sheet | **No.** It only calls system APIs — you choose the destination in the sheet; we never touch it | BSD-3-Clause | [pub.dev](https://pub.dev/packages/share_plus) |
| `gal` | 2.3.3 | Saves the share card into the **system photo library** | **No.** Write-only; it **never reads** your photos | BSD-3-Clause | [pub.dev](https://pub.dev/packages/gal) |
| `cryptography` | 2.9.0 | End-to-end encryption for cloud backup (HKDF-SHA256 + AES-256-GCM) | **No.** Pure Dart, no network | Apache-2.0 | [pub.dev](https://pub.dev/packages/cryptography) |

One dependency is **not** third-party, and we state it here too:

- `flutter_localizations`: Flutter's own (SDK-bundled) localization component. It makes built-in
  screens such as the open-source license page and date pickers render in Chinese.
  **It is not a third-party SDK, it collects nothing, and it makes no network calls.**

Three notes:

- **No advertising SDK, no analytics SDK, no crash-reporting SDK.** None of the libraries above
  sends anything to a third party.
- Our own code goes online only when **you** enable cloud backup, or when "Help improve the product"
  is on **and** the build has an endpoint configured — see 3.1 (the current release has none).
- **Development-only dependencies never ship**: `build_runner` / `drift_dev` (code generation) and
  `integration_test` (our own test harness) exist only in development and CI.
- **The table above lists direct dependencies only.** They pull in further transitive libraries
  (the Flutter framework, Skia, ICU, …). The complete list is available **inside the app** at
  "Me → Open-source licences" (Flutter's licence page enumerates every component shipped in the
  package). The per-library "does it collect anything" notes are hand-written for the libraries we
  chose; the authoritative answer for "what is in the package" is that page, not this table.

## 4. Permissions

The app declares three permissions; the second **only takes effect on old systems**, and the
third is **off by default** — it is only ever requested if you turn it on yourself:

| Permission | Why | Applies to |
|---|---|---|
| `android.permission.INTERNET` | Solely for the anonymous usage statistics in 2.2 (when the switch is ON) | All versions |
| `android.permission.WRITE_EXTERNAL_STORAGE` | Saving the "share card" image to the system gallery | **Android 9 and below only** (declared with `maxSdkVersion="29"`) |
| `android.permission.POST_NOTIFICATIONS` | Three **local** notifications: (1) the "training reminder" if you have not trained by your chosen time; (2) "rest finished", a cue when the rest between sets ends (since v1.53); (3) on the evening after a workout, (1) is replaced by a more specific "tomorrow: back day" (since 2026-10-05) | **Android 13 and above**; (1) is **off by default**, (2) only appears if you have already granted the permission, (3) can only appear while (1) is on |

Six notes on the third one (the notification permission):

- It is a **local notification**: the system fires it on this device (using an inexact alarm,
  so the exact-alarm special permission is not needed), and the text is computed on the device
  when the reminder is scheduled — **no network**, we neither know your training time nor
  whether you trained;
- The switch is **off by default**. The system permission prompt appears only when you
  turn it on yourself (Me → Preferences → Training reminder); if you decline, we never ask again;
- **No nagging after you train**: it reminds you only if you have not trained by that time
  that day; if you trained, it moves to the same time tomorrow;
- You can turn it off at any time, which also cancels the reminder already scheduled in the system;
- **The same permission also covers the "rest finished" cue** (since v1.53): Android shows no
  countdown on the lock screen, so when the rest between sets reaches zero we post a **local**
  notification (title "rest finished", body = what the next set is). It is **never uploaded,
  needs no new permission, and we never prompt for the permission because of it** — if you have
  not granted notifications, it simply does not appear (a permission dialog in the middle of a
  workout would be worse than a missing cue). In system settings these are **two separate
  channels** ("training reminder" / "rest finished") and can be turned off independently.
- **The sentence on the evening after a workout** (since 2026-10-05): while the training
  reminder is on, the reminder on a day you trained no longer says "not trained yet" —
  it tells you **which muscle group is next** (e.g. "tomorrow: back day"). It **asks for no
  extra permission, creates no extra channel and schedules no extra notification** — it uses
  the very same schedule as (1) and only makes the wording more specific; when there is no
  next muscle group to name (e.g. no training history yet) it falls back to the original
  sentence. Both the decision and the wording are computed on the device — **no network**.

Three notes on the second one:

- **Android 10+ does not need it at all** — modern Android writes to the gallery via
  MediaStore with no permission. Because we declare it with `android:maxSdkVersion="29"`,
  **users on newer systems never see it in the permission list.**
- It only grants image writes, and is used only when you tap "Save to gallery".
- The share card is **rendered on your device**: the image is drawn directly from the UI into
  a PNG and **is never uploaded to our servers**. Tapping "Share" hands the image to the
  system share sheet; which app you then pick (WeChat, Photos, …) is your choice, and that
  step is governed by that app's privacy policy.

**One more "read" permission shows up after packaging, and we want to be explicit about it.**
On **API ≤29** devices, merely declaring `WRITE_EXTERNAL_STORAGE` makes Android **imply** and
grant `READ_EXTERNAL_STORAGE` as well (`aapt2 dump badging` reports it as
`uses-implied-permission ... reason='requested WRITE_EXTERNAL_STORAGE'`). We **never read** your
photos or files — that permission comes from platform behaviour, not from a request of ours;
on API 30+ neither permission exists (MediaStore writes need none).

**(Updated 2026-10-05)** We used to carry `android:requestLegacyExternalStorage="true"` on
`application` — an **Android 10 (API 29) only** compatibility switch. **It has been removed**:
MediaStore works on that release too, so keeping it only left a switch a reviewer would ask
about. This note stays only to record that it existed and why it is no longer needed.
Verify the current package yourself: `aapt2 dump badging <apk> | grep permission`.

**On iOS we request exactly one photo permission, and it is add-only**:
`NSPhotoLibraryAddUsageDescription`, used to **write** the share card into your photo library.
We do **not** request read access (`NSPhotoLibraryUsageDescription`) — which is also why iOS
does not create a "练了么" album; the card lands in **Recents**. One album grouping less, in
exchange for "we never read your photo library" being literally true. Beyond this we request
no location, contacts, camera, microphone, notifications, or advertising identifier (IDFA)
on iOS.

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
| **Turn usage statistics on or off** | **It is off by default** (nobody is counted). To take part, **turn it on yourself** in Profile → Privacy & About → "Help improve the product". Both directions take effect immediately; no feature is affected |
| **Export the usage events** | Once that switch is on, Profile → Privacy & About also shows "Export statistics events": it exports the anonymous events stored on this device into a file (one JSON object per line) that you can keep or send to us. **While the switch is off, this entry does not appear** — nothing is being collected then |
| **Export all your data** | Profile → Data & Backup → "Export all records" — generates a CSV copied to your clipboard |
| **Delete all data** | Profile → Data & Backup → "Delete all data". After a confirmation prompt, local records and settings are wiped immediately |
| **Uninstall to delete** | Uninstalling the app removes the local database |

About "Export statistics events", three things up front:

- It is **read-only**: no network request, no queue clearing, no switch change — you can export again at any time;
- The exported file **contains the anonymous device identifier** (`device_id`). It is generated randomly on this device and is not linked to any account, but since the file is handed to you, we say so plainly;
- The export action **itself produces no event** (otherwise "logging a tap so you can get your data" would need yet another disclosure).

What deletion covers, to avoid misunderstanding:

- **Deleted**: all workout and set records, preferences (including all switches), **and any
  analytics events not yet uploaded**, and the anonymous analytics identifiers
  (`device_id` / session id / first-open timestamp) — with the honest consequence that this device
  then counts as a new device in aggregate statistics
- **Not deleted**: the built-in exercise catalog (351 exercises) — that is product content and
  contains nothing about you
- It is a **hard delete**, not a flag. Deletion cannot be undone, and we hold no backup that
  could restore it.
- **This release has cloud backup enabled** (see 3.1). Deleting all
data will ask whether to delete the cloud backup as well and close the account; the default is
  to delete both. The order is deliberate: the cloud copy is deleted **first**, and if that fails
  the whole operation stops. We would rather have you retry than leave you with local data gone
  and a cloud copy you can no longer open.

---

### 5.2 Complaints and reports

- **Channel**: `https://github.com/sdknwdtvpv-sys/sport/issues` (the contact in the table above).
- **Response time**: we answer within **15 working days**; if it takes longer we say why first.
- **Right to rectification**: workout records, body metrics and every setting can be edited in the app —
  the "All data" screen lets you edit records one by one, "Me" holds the settings.
- **Not satisfied with our answer?** You may complain to your local cyberspace or telecom authority.
  We will not treat you differently for doing so.

## 6. Retention

- On-device data: kept until you delete it (which is what a workout log should do).
- Pending outbox events: size-capped; over the cap, lower-priority events are dropped first
  (P0 workout data is retained preferentially).
- Server-side: **no server-side data exists today.**

---

## 7. Minors

This product is not directed at children under 14, and we do not knowingly collect their personal
information. If you are a guardian and believe we hold such information, please contact us through the contact details in the table at the top of this policy.

---

## 8. Changes to this policy

When this policy changes we will announce it in-app and in the release notes, and update the
effective date at the top. For material changes (for example, beginning real uploads) we will ask
for your consent separately.

<!-- 内部 -->

## Appendix A: where these statements come from

| Statement | Source |
|---|---|
| The 22 analytics events and their fields | `app/lib/features/workout/workout_controller.dart` (`track(...)` call sites) |
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

<!-- /内部 -->
