import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:app_core/config/app_config.dart';
import 'package:app_core/data/services/api_service.dart' show ApiException;
import 'package:app_core/data/services/service_providers.dart';
import 'package:app_core/session/current_user_provider.dart';
import 'checkout.dart';
import 'payment_order.dart';

/// The server's /payments routes, as the signed-in [userId].
class PaymentsApi {
  PaymentsApi(this._config, this._http, {required this.userId});

  final AppConfig _config;
  final http.Client _http;
  final int userId;

  Uri _uri(String path) => Uri.parse('${_config.apiBaseUrl}$path').replace(queryParameters: {'userId': '$userId'});

  Future<Object?> _send(String method, Uri uri, [Map<String, Object?>? body]) async {
    final request = http.Request(method, uri);
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final res = await http.Response.fromStream(await _http.send(request));
    if (res.statusCode >= 400) throw ApiException(res.statusCode, res.body);
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  /// Mine, newest first.
  Future<List<PaymentOrder>> mine() async => [
        for (final o in (await _send('GET', _uri('/payments/orders')))! as List) PaymentOrder.fromJson(o as Map<String, dynamic>),
      ];

  Future<PaymentOrder> get(int id) async =>
      PaymentOrder.fromJson((await _send('GET', _uri('/payments/orders/$id')))! as Map<String, dynamic>);

  /// Passes on what the checkout sheet answered; the server checks its
  /// signature (it holds the secret; this app doesn't).
  Future<PaymentOrder> confirm(int id, CheckoutPaid paid) async => PaymentOrder.fromJson(
        (await _send('POST', _uri('/payments/orders/$id/confirm'), {
          'providerPaymentId': paid.paymentId,
          'signature': paid.signature,
        }))! as Map<String, dynamic>,
      );
}

final paymentsApiProvider = Provider<PaymentsApi>(
  (ref) => PaymentsApi(
    ref.watch(appConfigProvider),
    ref.watch(apiHttpClientProvider),
    userId: ref.watch(currentUserProvider).requireValue!.id,
  ),
);

/// Your orders ("Your tickets").
final myOrdersProvider = FutureProvider.autoDispose<List<PaymentOrder>>((ref) => ref.watch(paymentsApiProvider).mine());
