# Micro Reader

An Android app that hands you your novel in tiny pieces, at random moments of
the day, as notifications. No server, no account, no Telegram: everything runs
on your phone.

## Install on your phone

1. Open this repo on GitHub → **Releases** (right-hand side) → latest build.
2. Download `micro-reader.apk` on your phone and open it. Android may ask you to
   allow "Install unknown apps" for your browser.
3. Open the app, allow notifications, then **Library → Add EPUB**.
4. **Settings → Send a test notification** to check reminders work on your
   phone.

Every push to `main` builds a new APK (GitHub → Actions → "Build APK").

## How it works

- **Import:** pick an `.epub`. The app cuts it into pieces of about 150–250
  words, always in story order, always at paragraph ends (a paragraph longer
  than 250 words is split at sentence ends). Headings start a new piece,
  images and tables stay with the text around them.
- **Notifications:** at random times inside your awake hours, with a minimum
  gap and a daily cap. Planned three days ahead; replanned whenever you read,
  change a setting or open the app.
- **Reader:** tap a notification to open the pending piece. It shows a
  "Previously…" line from the previous piece. **Done** unlocks after you have
  scrolled to the end and half the estimated reading time has passed.
  **Snooze** brings the same piece back in 20 minutes.
- **Never skips ahead:** the app only moves on when you press Done. Swipe a
  notification away and the same piece is simply pending until you read it.
  Use the arrows to re-read earlier pieces; that doesn't change your place or
  your stats.
- **Several books:** each book can be active or paused. Each notification picks
  one active book at random and always serves *that book's* next piece.
- **Goals:** "finish in N days" sets how many pieces a day you need (capped by
  your daily cap).

## Progress tab

- **Today's ring:** pieces read today vs. today's target.
- **Streak:** days in a row with at least one piece read. One missed day per
  calendar week (Mon–Sun) is forgiven.
- **Response rate:** share of notifications you reacted to (Done or Snooze)
  within an hour.
- **Pace:** projected finish date from your average pace, against your goal,
  with a small chart.

## Good to know

- **Android battery saver** can delay notifications. If they arrive late, go to
  Settings → Apps → Micro Reader → Battery → *Unrestricted*.
- Notifications are planned three days ahead, so open the app at least that
  often.
- Only EPUB is supported. Convert PDFs first (for example with Calibre).
- The awake window must be inside one day (for example 09:00–22:00).

## Build it yourself

You need the Flutter SDK, JDK 17 and the Android SDK.

```bash
bash tools/setup_android.sh   # generates android/ and patches it
flutter pub get
flutter test
flutter build apk --release   # build/app/outputs/flutter-apk/app-release.apk
```

`android/` is generated and not committed; `tools/patch_android.py` adds the
notification permissions and receivers.

## Layout

| Path | What |
| --- | --- |
| `lib/chunker.dart` | Cuts blocks into pieces; sentence splitting; "Previously…" |
| `lib/scheduler.dart` | Random notification times; daily target |
| `lib/stats.dart` | Streak, pace, response rate |
| `lib/epub_import.dart` | EPUB → text, images, tables |
| `lib/store.dart` | State on disk, actions, notification planning |
| `lib/ui/` | Screens |
| `test/` | Unit tests for all of the above |
