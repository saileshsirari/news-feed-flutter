import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'checkout_mobile.dart' if (dart.library.js_interop) 'checkout_web.dart' as impl;

/// What the payment sheet answered.
sealed class CheckoutResult {
  const CheckoutResult();
}

/// Paid. Not trusted on its own: the server checks [signature] (made with a
/// secret only the server and Razorpay have) before anything is confirmed.
class CheckoutPaid extends CheckoutResult {
  const CheckoutPaid({required this.paymentId, required this.orderId, required this.signature});
  final String paymentId;
  final String orderId;
  final String signature;
}

/// Closed without paying.
class CheckoutCancelled extends CheckoutResult {
  const CheckoutCancelled();
}

/// The payment didn't go through (card declined, network...); nothing was charged.
class CheckoutFailed extends CheckoutResult {
  const CheckoutFailed(this.message);
  final String message;
}

/// The provider's payment sheet. On phones, Razorpay's own SDK; in a
/// browser, its Checkout.js. Takes the options the server sent with the
/// order (key id, order id, amount) and nothing secret.
abstract interface class Checkout {
  Future<CheckoutResult> open(Map<String, dynamic> options);
}

final checkoutProvider = Provider<Checkout>((ref) => impl.platformCheckout());
