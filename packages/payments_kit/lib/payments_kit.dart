/// Paying for things through the server's payments module: money
/// ([Money]), orders ([PaymentOrder], [PaymentsApi]) and the provider's
/// checkout sheet ([Checkout]: Razorpay's SDK on phones, Checkout.js in a
/// browser). Any mini-app that sells something uses it: communities for
/// event tickets, taxi for fares. Like a shop's card machine: each shop
/// rings up its own sale, the machine is the same.
library;

export 'src/checkout.dart';
export 'src/payment_order.dart';
export 'src/payments_api.dart';
