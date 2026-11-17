import 'package:http/http.dart' as http;

/// Adds `X-Org: <id>` to every request: which organisation the app is
/// showing. Like pressing a floor's button in a shared office building:
/// the server checks you work on that floor, then everything the request
/// does happens there. With no org yet (still loading, or an older server
/// without organisations), requests go without it and the server uses the
/// person's own.
class OrgHeaderClient extends http.BaseClient {
  OrgHeaderClient(this._inner, this.orgId);

  final http.Client _inner;
  final int? orgId;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final id = orgId;
    if (id != null) request.headers['X-Org'] = '$id';
    return _inner.send(request);
  }
}
