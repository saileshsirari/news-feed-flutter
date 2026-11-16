import 'dart:async';

import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import 'checkout.dart';

Checkout platformCheckout() => _PhoneCheckout();

/// Razorpay's sheet or Stripe's, by what the server sent.
class _PhoneCheckout implements Checkout {
  final _razorpay = _RazorpayCheckout();
  final _stripe = _StripeCheckout();

  @override
  Future<CheckoutResult> open(Map<String, dynamic> options) =>
      isStripeCheckout(options) ? _stripe.open(options) : _razorpay.open(options);
}

/// Stripe's PaymentSheet (Android / iOS): cards, Google Pay, Apple Pay,
/// whatever's switched on in the Stripe dashboard. It pays the order's
/// PaymentIntent with its client secret; the server then asks Stripe
/// whether it really succeeded (see the server's stripe.ts).
class _StripeCheckout implements Checkout {
  @override
  Future<CheckoutResult> open(Map<String, dynamic> options) async {
    final intentId = options['paymentIntentId'] as String;
    try {
      // The publishable key is public (it's in every Stripe app); it comes
      // from the server so test and live keys switch without an app update.
      Stripe.publishableKey = options['publishableKey'] as String;
      await Stripe.instance.applySettings();
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: options['clientSecret'] as String,
          merchantDisplayName: options['merchantName'] as String? ?? 'News Feed',
        ),
      );
      await Stripe.instance.presentPaymentSheet();
      // For Stripe the payment's id is the PaymentIntent's; nothing to sign.
      return CheckoutPaid(paymentId: intentId, orderId: intentId, signature: '');
    } on StripeException catch (e) {
      if (e.error.code == FailureCode.Canceled) return const CheckoutCancelled();
      return CheckoutFailed(e.error.localizedMessage ?? e.error.message ?? 'The payment didn\'t go through.');
    } on Exception catch (e) {
      return CheckoutFailed('The payment sheet couldn\'t open ($e).');
    }
  }
}

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
      finish(
        r.paymentId == null || r.signature == null
            ? const CheckoutFailed('The payment app gave no confirmation.')
            : CheckoutPaid(paymentId: r.paymentId!, orderId: r.orderId ?? '', signature: r.signature!),
      );
    });
    razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) {
      finish(
        r.code == Razorpay.PAYMENT_CANCELLED
            ? const CheckoutCancelled()
            : CheckoutFailed(r.message ?? 'The payment didn\'t go through.'),
      );
    });
    // A wallet app took over (Paytm, say): the server hears from Razorpay when it's paid.
    razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (_) => finish(const CheckoutCancelled()));
    razorpay.open(options);
    return done.future;
  }
}
