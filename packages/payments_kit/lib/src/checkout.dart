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

/// The provider's payment sheet, for whichever company the server chose
/// for the order's money:
///
/// * Razorpay (rupees): its SDK on phones, Checkout.js in a browser. Its
///   "paid" answer is signed, and the server checks the signature.
/// * Stripe (euros, dollars): its PaymentSheet on phones. Its "paid" comes
///   with no signature; the server asks Stripe itself before believing it.
///   (Not in the browser yet: there it says so, and cash still works.)
///
/// Takes the options the server sent with the order (public key, order,
/// amount; for Stripe, the order's client secret) and nothing secret.
abstract interface class Checkout {
  Future<CheckoutResult> open(Map<String, dynamic> options);
}

/// Options for Stripe's sheet (the server's Stripe checkout has these),
/// rather than Razorpay's.
bool isStripeCheckout(Map<String, dynamic> options) =>
    options['clientSecret'] is String && options['publishableKey'] is String;

final checkoutProvider = Provider<Checkout>((ref) => impl.platformCheckout());
