import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'package:feature_communities/payments/checkout.dart';

Checkout platformCheckout() => _CheckoutJs();

/// Razorpay's Checkout.js, loaded the first time someone pays (not on every
/// page load: most visits never pay for anything).
class _CheckoutJs implements Checkout {
  static const _scriptUrl = 'https://checkout.razorpay.com/v1/checkout.js';
  Future<void>? _loading;

  Future<void> _load() => _loading ??= () {
        final loaded = Completer<void>();
        final script = web.HTMLScriptElement()
          ..src = _scriptUrl
          ..async = true;
        script.onload = ((web.Event _) => loaded.complete()).toJS;
        script.onerror = ((web.Event _) {
          _loading = null; // try again next time
          loaded.completeError(StateError('couldn\'t load the payment page'));
        }).toJS;
        web.document.head!.append(script);
        return loaded.future;
      }();

  @override
  Future<CheckoutResult> open(Map<String, dynamic> options) async {
    try {
      await _load();
    } on StateError {
      return const CheckoutFailed('Couldn\'t load the payment page. Check your connection.');
    }
    final done = Completer<CheckoutResult>();
    void finish(CheckoutResult result) {
      if (!done.isCompleted) done.complete(result);
    }

    final jsOptions = options.jsify()! as JSObject;
    jsOptions['handler'] = ((JSObject r) {
      String? field(String name) => (r[name] as JSString?)?.toDart;
      final paymentId = field('razorpay_payment_id');
      final signature = field('razorpay_signature');
      finish(paymentId == null || signature == null
          ? const CheckoutFailed('The payment page gave no confirmation.')
          : CheckoutPaid(paymentId: paymentId, orderId: field('razorpay_order_id') ?? '', signature: signature));
    }).toJS;
    final modal = JSObject()..['ondismiss'] = (() => finish(const CheckoutCancelled())).toJS;
    jsOptions['modal'] = modal;

    final constructor = web.window['Razorpay'] as JSFunction;
    final razorpay = constructor.callAsConstructor<JSObject>(jsOptions);
    razorpay.callMethod('on'.toJS, 'payment.failed'.toJS, ((JSObject r) {
      final error = r['error'] as JSObject?;
      // The sheet stays open for another try; this is reported only if they then close it.
      final message = (error?['description'] as JSString?)?.toDart;
      if (message != null) web.console.warn('payment attempt failed: $message'.toJS);
    }).toJS);
    razorpay.callMethod('open'.toJS);
    return done.future;
  }
}
