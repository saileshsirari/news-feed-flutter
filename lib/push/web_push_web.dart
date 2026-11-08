import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'web_push_client.dart';

WebPushClient createWebPushClient() => _BrowserPush();

class _BrowserPush implements WebPushClient {
  /// Its own scope, so it never touches Flutter's own files (see push_sw.js).
  static const _worker = 'push_sw.js';
  static const _scope = 'push/';

  @override
  bool get supported =>
      web.window.isSecureContext && web.window.navigator.has('serviceWorker') && web.window.has('PushManager');

  @override
  String get permission => web.window.has('Notification') ? web.Notification.permission : 'denied';

  @override
  Future<String> requestPermission() async => (await web.Notification.requestPermission().toDart).toDart;

  Future<web.ServiceWorkerRegistration> _registration() async {
    final registration = await web.window.navigator.serviceWorker
        .register(_worker.toJS, web.RegistrationOptions(scope: _scope))
        .toDart;
    // Subscribing needs an active worker. navigator.serviceWorker.ready
    // only waits for the worker controlling this page, which ours (scope
    // "push/") never is, so wait for it to activate ourselves.
    for (var i = 0; i < 50 && registration.active == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return registration;
  }

  @override
  Future<Map<String, dynamic>> subscribe(String vapidPublicKey) async {
    final pushManager = (await _registration()).pushManager;
    final existing = await pushManager.getSubscription().toDart;
    final subscription = existing ??
        await pushManager
            .subscribe(web.PushSubscriptionOptionsInit(
              // Every push shows a notification (Chrome requires it).
              userVisibleOnly: true,
              applicationServerKey: _base64UrlBytes(vapidPublicKey).toJS,
            ))
            .toDart;
    return jsonDecode(web.window.JSON_stringify(subscription.toJSON())) as Map<String, dynamic>;
  }

  @override
  Future<void> unsubscribe() async {
    final subscription = await (await _registration()).pushManager.getSubscription().toDart;
    await subscription?.unsubscribe().toDart;
  }

  static Uint8List _base64UrlBytes(String key) => base64Url.decode(key.padRight((key.length + 3) ~/ 4 * 4, '='));
}

extension on web.Window {
  // ignore: non_constant_identifier_names
  String JSON_stringify(JSAny? value) => _stringify(value).toDart;
}

@JS('JSON.stringify')
external JSString _stringify(JSAny? value);
