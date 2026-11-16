import 'package:flutter_test/flutter_test.dart';
import 'package:payments_kit/payments_kit.dart';

void main() {
  test('Stripe options (public key + client secret) open Stripe\'s sheet; Razorpay\'s open Razorpay\'s', () {
    expect(
      isStripeCheckout({'publishableKey': 'pk_test_x', 'clientSecret': 'pi_1_secret_y', 'paymentIntentId': 'pi_1'}),
      isTrue,
    );
    expect(isStripeCheckout({'key': 'rzp_test_x', 'order_id': 'order_1', 'amount': 39600}), isFalse);
  });

  test('Stripe\'s "paid" carries the PaymentIntent and no signature: the server asks Stripe', () {
    const paid = CheckoutPaid(paymentId: 'pi_1', orderId: 'pi_1', signature: '');
    expect(paid.paymentId, 'pi_1');
  });
}
