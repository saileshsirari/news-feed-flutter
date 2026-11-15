import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:app_core/data/services/service_providers.dart';
import 'package:feature_communities/events/event.dart';
import 'package:feature_communities/events/event_screen.dart';
import 'package:feature_communities/payments/checkout.dart';
import 'package:feature_communities/payments/my_tickets_screen.dart';
import 'package:feature_communities/payments/payment_order.dart';
import 'package:app_core/session/current_user_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final start = DateTime.utc(2026, 12, 20, 12);

/// A paid event (₹499) as the server would send it, with [myRsvp] for me.
Map<String, dynamic> paidEvent({String? myRsvp, bool refundable = true}) => {
      'id': 7,
      'community': {'id': 9, 'name': 'Riders', 'slug': 'riders'},
      'title': 'Sunset ride',
      'startsAt': start.millisecondsSinceEpoch,
      'endsAt': start.add(const Duration(hours: 2)).millisecondsSinceEpoch,
      'timeZone': 'Asia/Kolkata',
      'utcOffsetMinutes': 330,
      'location': {'kind': 'in_person', 'placeName': 'Nandi Hills'},
      'capacity': 10,
      'goingCount': myRsvp == 'going' ? 1 : 0,
      'waitlistCount': 0,
      'spotsLeft': 9,
      'price': {'amountMinor': 49900, 'currency': 'INR'},
      // Refunds until a day before (or a date already gone).
      'refundableUntil': (refundable ? start.subtract(const Duration(days: 1)) : DateTime.utc(2020)).millisecondsSinceEpoch,
      'cancelled': false,
      'past': false,
      'myRsvp': myRsvp,
      'canManage': false,
      'canRsvp': true,
    };

Map<String, dynamic> order({String status = 'pending', bool payable = true}) => {
      'id': 11,
      'purpose': 'event_ticket',
      'itemId': 7,
      'description': 'Ticket: Sunset ride',
      'amountMinor': 49900,
      'currency': 'INR',
      'status': status,
      'createdAt': DateTime.utc(2026, 11, 14).millisecondsSinceEpoch,
      'expiresAt': DateTime.utc(2026, 11, 14, 0, 10).millisecondsSinceEpoch,
      'paidAt': status == 'paid' ? DateTime.utc(2026, 11, 14).millisecondsSinceEpoch : null,
      'note': status == 'refunding' ? 'you cancelled before the refund deadline' : null,
      'checkout': payable ? {'provider': 'razorpay', 'options': {'key': 'rzp_test_x', 'order_id': 'order_abc', 'amount': 49900}} : null,
    };

/// Answers [result] and remembers what it was opened with.
class FakeCheckout implements Checkout {
  FakeCheckout(this.result);
  final CheckoutResult result;
  final opened = <Map<String, dynamic>>[];

  @override
  Future<CheckoutResult> open(Map<String, dynamic> options) async {
    opened.add(options);
    return result;
  }
}

void main() {
  late List<http.Request> requests;
  late String mine; // my RSVP on the server: null, held or going
  late bool refundable;

  setUp(() {
    SharedPreferences.setMockInitialValues({'id': 1, 'username': 'me', 'followerCount': 0});
    requests = [];
    mine = 'none';
    refundable = true;
  });

  http.Client server() => MockClient((request) async {
        requests.add(request);
        http.Response json(Object? body, [int status = 200]) => http.Response.bytes(utf8.encode(jsonEncode(body)), status,
            headers: {'content-type': 'application/json; charset=utf-8'});
        Map<String, dynamic> event() => paidEvent(myRsvp: mine == 'none' ? null : mine, refundable: refundable);
        switch ((request.method, request.url.path)) {
          case ('POST', '/events/7/ticket'):
            mine = 'held';
            return json({'event': event(), 'order': order()}, 201);
          case ('POST', '/payments/orders/11/confirm'):
            mine = 'going';
            return json(order(status: 'paid', payable: false));
          case ('DELETE', '/events/7/rsvp'):
            mine = 'none';
            return json(event());
          case ('GET', '/events/7'):
            return json(event());
          case ('GET', '/payments/orders'):
            return json([order(status: 'paid', payable: false), order(status: 'refunding', payable: false), order(status: 'expired')]);
          case ('GET', '/events/7/attendees' || '/communities/9/events' || '/events/upcoming'):
            return json({'items': [], 'nextCursor': null});
        }
        return json({'error': 'not found'}, 404);
      });

  Future<FakeCheckout> show(WidgetTester tester, CheckoutResult answer, {Widget home = const EventScreen(eventId: 7)}) async {
    final checkout = FakeCheckout(answer);
    final container = ProviderContainer.test(overrides: [
      apiHttpClientProvider.overrideWithValue(server()),
      checkoutProvider.overrideWithValue(checkout),
    ]);
    await tester.runAsync(() => container.read(currentUserProvider.future));
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp(home: home)));
    await settle(tester);
    return checkout;
  }

  test('money is whole paise, written the way the device\'s region writes numbers', () {
    expect('${const Money(49900, 'INR')}', '₹499');
    expect('${const Money(49950, 'INR')}', '₹499.50');
    // Written the way the device's region writes numbers; still rupees.
    expect(const Money(10000000, 'INR').format(locale: 'en_IN'), '₹1,00,000');
    expect(const Money(10000000, 'INR').format(locale: 'en_US'), '₹100,000');
    expect(const Money(10000000, 'INR').format(locale: 'en-GB'), '₹100,000');
    expect(const Money(10000050, 'INR').format(locale: 'de_DE'), '100.000,50\u00a0₹'); // a no-break space before ₹
    expect(const Money(49900, 'INR').format(locale: 'xx_YY'), '₹499'); // unknown: English
  });

  test('what an organiser types reads as paise, exactly', () {
    int? paise(String text) => Money.tryParse(text)?.amountMinor;
    expect(paise('499'), 49900);
    expect(paise('499.5'), 49950);
    expect(paise(' 1.05 '), 105);
    expect(paise('4.999'), isNull);
    expect(paise('-5'), isNull);
    expect(paise('abc'), isNull);
  });

  test('a paid event and a held spot from the server', () {
    final e = Event.fromJson(paidEvent(myRsvp: 'held'));
    expect(e.isPaid, isTrue);
    expect(e.price, const Money(49900, 'INR'));
    expect(e.myRsvp, RsvpStatus.held);
    expect(e.refundableNow, isTrue);
    expect(Event.fromJson(paidEvent(refundable: false)).refundableNow, isFalse);
  });

  testWidgets('buying: the server\'s checkout options open the sheet, and its answer goes back to be checked', (tester) async {
    final checkout = await show(tester, const CheckoutPaid(paymentId: 'pay_1', orderId: 'order_abc', signature: 'sig_1'));
    expect(find.text('₹499 a ticket'), findsOneWidget);

    await tester.tap(find.text('Buy ticket · ₹499'));
    await settle(tester);

    expect(checkout.opened.single, {'key': 'rzp_test_x', 'order_id': 'order_abc', 'amount': 49900});
    final confirm = requests.singleWhere((r) => r.url.path == '/payments/orders/11/confirm');
    expect(jsonDecode(confirm.body), {'providerPaymentId': 'pay_1', 'signature': 'sig_1'});
    expect(find.text('Paid. You\'re going!'), findsOneWidget);
    expect(find.text('You have a ticket · Cancel'), findsOneWidget);
  });

  testWidgets('closing the sheet lets the held spot go, and charges nothing', (tester) async {
    await show(tester, const CheckoutCancelled());
    await tester.tap(find.text('Buy ticket · ₹499'));
    await settle(tester);

    expect(requests.where((r) => r.url.path == '/payments/orders/11/confirm'), isEmpty);
    expect(requests.where((r) => r.method == 'DELETE' && r.url.path == '/events/7/rsvp'), hasLength(1));
    expect(find.text('Payment cancelled. Nothing was charged.'), findsOneWidget);
    expect(find.text('Buy ticket · ₹499'), findsOneWidget);
  });

  testWidgets('cancelling a ticket says whether the money comes back', (tester) async {
    mine = 'going';
    await show(tester, const CheckoutCancelled());
    await tester.tap(find.text('You have a ticket · Cancel'));
    await tester.pumpAndSettle();
    expect(find.textContaining('You\'ll get ₹499 back'), findsOneWidget);
    await tester.tap(find.text('Cancel and refund'));
    await settle(tester);
    expect(find.text('Cancelled. Your refund is on its way.'), findsOneWidget);
  });

  testWidgets('after the deadline, cancelling is plainly without a refund', (tester) async {
    mine = 'going';
    refundable = false;
    await show(tester, const CheckoutCancelled());
    expect(find.text('No refunds now (the deadline has passed)'), findsOneWidget);
    await tester.tap(find.text('You have a ticket · Cancel'));
    await tester.pumpAndSettle();
    expect(find.textContaining('you won\'t get your ₹499 back'), findsOneWidget);
    expect(find.text('Cancel without refund'), findsOneWidget);
  });

  testWidgets('your tickets: paid and refunding shown, never-paid ones left out', (tester) async {
    await show(tester, const CheckoutCancelled(), home: const MyTicketsScreen());
    expect(find.text('Paid'), findsOneWidget);
    expect(find.text('Refund on its way'), findsOneWidget);
    expect(find.text('Not paid'), findsNothing);
    expect(find.text('Sunset ride'), findsNWidgets(2));
  });
}

/// Lets the fake server's futures finish, then draws.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
  }
}
