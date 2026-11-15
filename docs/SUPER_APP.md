# The super app: mini-apps on a Home grid

The app is a set of **mini-apps** (feed, chat, communities, taxi) on a
shared **core**. Think of a shopping mall: the core is the building (doors,
lights, security, the directory board), each mini-app is a shop. Shops never
knock through each other's walls; they send customers by address.

```
lib/main.dart ─▶ mini_apps.dart ─▶ [feed]  [chat]  [communities]
                                     │        │          │
                                     └────────┴──────────┴──▶ packages/app_core
```

## Packages

| Package | What's in it |
|---|---|
| `packages/app_core` | sign-in and session, API client and models, socket, push, settings, theme, Home shell, inbox, `MiniApp` |
| `packages/feature_feed` | feed, posts, comments, likes, profiles |
| `packages/feature_chat` | chats, end-to-end encryption (MLS), calls, presence |
| `packages/feature_communities` | communities, events, near me, tickets |

Rules (kept by each pubspec):

* `app_core` depends on no `feature_*` package.
* A mini-app depends on `app_core` only. The one exception: communities shows
  its posts with the feed's post widgets (`package:feature_feed/posts.dart`),
  one way only.
* Another mini-app's **screens** are opened by link, never imported:
  `openAppLink(context, AppLinks.profile(42))` → `app://feed/profile/42`.
  If that mini-app isn't in this build, or the server has it off, the person
  sees "That isn't available in this app."

## A mini-app

`MiniApp` (`app_core/lib/mini_app/mini_app.dart`) is everything the shell
knows about one:

| Member | For |
|---|---|
| `info` | id, name, icon, colour, `isGlobal` (the tile, before any code loads) |
| `buildHome` | its first screen, opened full screen from Home (back = Home) |
| `screenFor(link)` | its screens other mini-apps and notifications open |
| `showPush(data, appOpen:)` | shows a push meant for it |
| `badgeCount` | the number on its tile (chat: unread chats) |
| `wrapSignedIn` | listeners alive while signed in (chat: call banner, sync) |
| `overrides`, `initialise` | app-wide setup (chat: media sealer, MLS library) |
| `onDeviceRegistered`, `onSignOut` | per-device setup, per-user cleanup |

## Which mini-apps show

A tile shows when the mini-app is **compiled in** (listed in
`lib/mini_apps.dart`) **and on at the server** (`GET /config/apps`, from the
server's `ENABLED_MODULES`). If the server can't be asked (offline, or an
older server), every compiled-in mini-app shows.

The same answer carries the map settings (tile URL and credit line, whether
place search is on, the routing provider), so production can move off
OpenStreetMap's free servers without an app update.

## Standalone apps

`lib/main_chat.dart` is chat on its own: the same `runSuperApp` with one
mini-app.

```bash
flutter run -t lib/main_chat.dart
```

To split one into its own repository later: copy its `main_*.dart`,
`packages/app_core`, its `feature_*` package and the shared packages it uses.

## Web and phones

`lib/mini_apps.dart` imports feed and communities with `deferred as`. On the
web each becomes its own `main.dart.js_N.part.js`, downloaded the first time
it's opened (`MiniAppSlot.deferred`). On Android and iOS deferred imports are
compiled in as usual: iOS can't download code, and Play Store deferred
components aren't set up. Chat is global (messages and calls reach you in any
mini-app), so it loads at start everywhere.

## Adding a mini-app (as taxi was)

1. `packages/feature_taxi` with `taxi_info.dart` (a `MiniAppInfo`) and
   `feature_taxi.dart` (`TaxiMiniApp extends MiniApp`), depending on
   `app_core` (and `geo_kit`).
2. Add it to the app's pubspec and a `MiniAppSlot.deferred(taxiInfo, ...)`
   line in `lib/mini_apps.dart`.
3. Server: a `taxi` module, and `{ id: "taxi", needs: ["taxi"] }` in
   `src/modules/appconfig/clientConfig.ts`.

Taxi itself (rides, live tracking, driver mode) is described in the
server's `docs/TAXI.md`. It listens on the shared socket with
`AppSocket.watch(...)`, the general form of `watchPost` (counted, and sent
again after a reconnect).

## Region and units

* Distances: `formatDistance` in geo_kit uses km, or miles where the device's
  region uses them (USA, UK).
* The place picker opens on a saved place, else the app's rough idea of where
  you are, else the middle of the device's country (`defaultMapView`); it
  never asks for the location by itself.
* Prices: `Money` is written the device region's way (₹1,00,000 in India,
  ₹100,000 in the USA); INR is still the only ticket currency.
