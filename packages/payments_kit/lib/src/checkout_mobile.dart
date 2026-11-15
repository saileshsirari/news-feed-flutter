import 'dart:async';

import 'package:razorpay_flutter/razorpay_flutter.dart';

import 'checkout.dart';

Checkout platformCheckout() => _RazorpayCheckout();

/// Razorpay's Android / iOS SDK: it shows its own sheet (cards, UPI apps,
/// net banking) and answers through callbacks, turned here into one Future.
class _RazorpayCheckout implements Checkout {
  @override
  Future<CheckoutResult> open(Map<String, dynamic> options) {
    final razorpay = Razorpay();
    final done = Completer<CheckoutResult>();
    void finish(CheckoutResult result) {
      if (!done.isCompleted) done.complete(result);
      razorpay.clear();
    }

    razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse r) {
      finish(r.paymentId == null || r.signature == null
          ? const CheckoutFailed('The payment app gave no confirmation.')
          : CheckoutPaid(paymentId: r.paymentId!, orderId: r.orderId ?? '', signature: r.signature!));
    });
    razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) {
      finish(r.code == Razorpay.PAYMENT_CANCELLED
          ? const CheckoutCancelled()
          : CheckoutFailed(r.message ?? 'The payment didn\'t go through.'));
    });
    // A wallet app took over (Paytm, say): the server hears from Razorpay when it's paid.
    razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (_) => finish(const CheckoutCancelled()));
    razorpay.open(options);
    return done.future;
  }
}
