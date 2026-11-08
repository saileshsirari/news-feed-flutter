# Push notifications

New chat messages reach a device even when the app is closed or in the
background. The server's side is `src/modules/push` in news-feed-system.

| Platform | How | Text goes through Google/Apple? |
|---|---|---|
| Web | Web Push (open standard, our own VAPID key, no Firebase) | Encrypted for that browser by the standard: Google's push service can't read it |
| Android | FCM | No: only ids. The app wakes, fetches the message from our server, shows it |
| iOS | FCM (via Apple's APNs) | No: a "New message" placeholder; a Notification Service Extension will replace it with the real text |

Pushes go to every device of everyone else in the chat. The app decides
whether to show one (not while you're looking at the app).

## In the app

- `lib/push/push_registration.dart`: turning notifications on or off for
  this device (Settings → Notifications), and re-sending this device's
  address on every start.
- `lib/push/push_channel.dart` (Web Push), `lib/push/fcm_channel.dart`
  (FCM), `lib/push/push_setup.dart` (Firebase start-up, and what happens
  when a push arrives with the app in the background).
- `web/push_sw.js`: the browser's service worker that shows web
  notifications.
- Notifications need a signed-in account: test accounts have no registered
  device to push to.

## Setup

**Android**: Firebase project `news-feed-4b7a0`. Its
`android/app/google-services.json` comes from the Firebase console
(Project settings → Your apps) and isn't in git.

**Server**: `FCM_PROJECT_ID`, `FCM_SERVICE_ACCOUNT_FILE` (the service
account key, never in git), `WEBPUSH_VAPID_PUBLIC_KEY`,
`WEBPUSH_VAPID_PRIVATE_KEY`, `WEBPUSH_SUBJECT`.

**iOS, once there's an Apple Developer account** (the code is ready;
until then iOS simply has no push):

1. Apple Developer → Keys → create a key with **Apple Push Notifications
   service (APNs)**; download the `.p8`, note its Key ID and the Team ID.
2. Firebase console → Project settings → Cloud Messaging → Apple app
   configuration → upload that APNs key.
3. Firebase console → add an **iOS app** with bundle id
   `com.newsfeed.newsFeedFlutter`; download `GoogleService-Info.plist` into
   `ios/Runner/` (add it to the Runner target in Xcode).
4. Xcode → Runner → Signing & Capabilities → add **Push Notifications**
   (creates the `aps-environment` entitlement). `remote-notification` is
   already in Info.plist.
5. Later, for the real text instead of "New message": add a
   **Notification Service Extension** target that fetches the message
   (like `handlePushInBackground` does on Android) and replaces the text.
