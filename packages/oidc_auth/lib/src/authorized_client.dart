import 'package:http/http.dart' as http;

/// An [http.Client] that adds `Authorization: Bearer <token>` to every
/// request, when there is a token. With none (signed out, or a development
/// login), requests go out unchanged.
///
/// Only for the app's own API: never wrap the client that uploads to a
/// storage bucket's presigned URL, which mustn't see the token.
class AuthorizedClient extends http.BaseClient {
  AuthorizedClient(this._accessToken, [http.Client? inner]) : _inner = inner ?? http.Client();

  final Future<String?> Function() _accessToken;
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final token = await _accessToken();
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
