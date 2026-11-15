import 'package:intl/intl.dart';

/// A price: whole paise (or cents) and a currency, never a decimal.
/// `Money(49900, 'INR')` is ₹499.
class Money {
  const Money(this.amountMinor, this.currency);

  final int amountMinor;
  final String currency;

  /// What someone typed, "499" or "499.50", as paise; null if it isn't a
  /// price (more than two decimals, a sign, letters). Parsed as text, never
  /// through a double, so "1.05" is exactly 105 paise.
  static Money? tryParse(String text, {String currency = 'INR'}) {
    final match = RegExp(r'^(\d{1,6})(?:\.(\d{1,2}))?$').firstMatch(text.trim());
    if (match == null) return null;
    return Money(int.parse(match[1]!) * 100 + int.parse((match[2] ?? '0').padRight(2, '0')), currency);
  }

  static Money? fromJson(Object? json) => json is Map<String, dynamic>
      ? Money(json['amountMinor'] as int, json['currency'] as String)
      : null;

  /// "₹499", or "₹499.50" when there are paise.
  @override
  String toString() {
    final whole = amountMinor % 100 == 0;
    return NumberFormat.currency(
      locale: 'en_IN',
      name: currency,
      symbol: NumberFormat.simpleCurrency(name: currency).currencySymbol,
      decimalDigits: whole ? 0 : 2,
    ).format(amountMinor / 100);
  }

  @override
  bool operator ==(Object other) => other is Money && other.amountMinor == amountMinor && other.currency == currency;

  @override
  int get hashCode => Object.hash(amountMinor, currency);
}

enum OrderStatus { pending, paid, expired, refunding, refunded, failed }

/// An order as its buyer sees it (the server's OrderView).
class PaymentOrder {
  const PaymentOrder({
    required this.id,
    required this.purpose,
    required this.itemId,
    required this.description,
    required this.price,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    this.paidAt,
    this.refundedAt,
    this.note,
    this.checkoutProvider,
    this.checkoutOptions,
  });

  factory PaymentOrder.fromJson(Map<String, dynamic> json) {
    DateTime? at(String key) =>
        json[key] == null ? null : DateTime.fromMillisecondsSinceEpoch(json[key] as int, isUtc: true);
    final checkout = json['checkout'] as Map<String, dynamic>?;
    return PaymentOrder(
      id: json['id'] as int,
      purpose: json['purpose'] as String,
      itemId: json['itemId'] as int,
      description: json['description'] as String,
      price: Money(json['amountMinor'] as int, json['currency'] as String),
      status: OrderStatus.values.byName(json['status'] as String),
      createdAt: at('createdAt')!,
      expiresAt: at('expiresAt')!,
      paidAt: at('paidAt'),
      refundedAt: at('refundedAt'),
      note: json['note'] as String?,
      checkoutProvider: checkout?['provider'] as String?,
      checkoutOptions: checkout?['options'] as Map<String, dynamic>?,
    );
  }

  final int id;

  /// "event_ticket"; [itemId] is then the event's id.
  final String purpose;
  final int itemId;
  final String description;
  final Money price;
  final OrderStatus status;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? paidAt;
  final DateTime? refundedAt;

  /// Why it was refunded, say.
  final String? note;

  /// While it can still be paid: which provider's checkout, and its options.
  final String? checkoutProvider;
  final Map<String, dynamic>? checkoutOptions;

  bool get isTicket => purpose == 'event_ticket';

  /// "Paid", "Refund on its way"...
  String get statusLabel => switch (status) {
        OrderStatus.pending => 'Waiting for payment',
        OrderStatus.paid => 'Paid',
        OrderStatus.expired => 'Not paid',
        OrderStatus.refunding => 'Refund on its way',
        OrderStatus.refunded => 'Refunded',
        OrderStatus.failed => 'Failed',
      };
}
