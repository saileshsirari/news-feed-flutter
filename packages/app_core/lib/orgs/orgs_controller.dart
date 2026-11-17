import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/services/service_providers.dart';
import '../session/current_user_provider.dart';
import 'org.dart';
import 'orgs_api.dart';

/// My organisations, and the one the app is showing.
@immutable
class OrgsState {
  const OrgsState({required this.orgs, this.currentId});

  /// None: signed out, or a server from before organisations (then the app
  /// works as it always did, with no switcher).
  static const none = OrgsState(orgs: []);

  final List<Org> orgs;
  final int? currentId;

  Org? get current {
    for (final org in orgs) {
      if (org.id == currentId) return org;
    }
    return null;
  }
}

/// Beautiful Apps, everyone's organisation: the one to start in, if I'm in it.
const defaultOrgId = 1;

/// Which organisation the app is showing, and switching between them, like
/// switching Slack workspaces. The choice is remembered per account on this
/// device.
///
/// Switching changes [currentOrgIdProvider], which the API client watches
/// (it adds X-Org), so everything built on the API (the Home grid, each
/// mini-app's data, the socket) loads again for the new org by itself.
/// Mini-app screens are closed while switching (it's done from Home), so
/// none is left showing the old org's data.
class OrgsController extends AsyncNotifier<OrgsState> {
  static String _savedKey(int userId) => 'orgs.current.$userId';

  OrgsApi _api(int userId) => OrgsApi(ref.read(appConfigProvider), ref.read(accountHttpClientProvider), userId: userId);

  @override
  Future<OrgsState> build() async {
    final user = await ref.watch(currentUserProvider.future);
    if (user == null) return OrgsState.none;
    final List<Org> orgs;
    try {
      orgs = await _api(user.id).mine();
    } on Object catch (e) {
      // An older server, or offline: carry on without organisations (no
      // X-Org; the server uses the person's own).
      debugPrint('[orgs] couldn\'t load my organisations: $e');
      return OrgsState.none;
    }
    final saved = await _saved(user.id);
    return OrgsState(orgs: orgs, currentId: _pick(orgs, saved));
  }

  /// The one remembered, if I'm still in it; else Beautiful Apps; else my first.
  static int? _pick(List<Org> orgs, int? wanted) {
    bool has(int? id) => id != null && orgs.any((o) => o.id == id);
    if (has(wanted)) return wanted;
    if (has(defaultOrgId)) return defaultOrgId;
    return orgs.isEmpty ? null : orgs.first.id;
  }

  Future<int?> _saved(int userId) async {
    try {
      return (await SharedPreferences.getInstance()).getInt(_savedKey(userId));
    } on Object {
      return null; // no storage (tests): start in the default
    }
  }

  Future<void> _remember(int userId, int orgId) async {
    try {
      await (await SharedPreferences.getInstance()).setInt(_savedKey(userId), orgId);
    } on Object {
      // Not remembered: next start opens the default one. Nothing else to do.
    }
  }

  /// Shows [orgId] (one of mine) from now on.
  Future<void> switchTo(int orgId) async {
    final now = state.value;
    final user = ref.read(currentUserProvider).value;
    if (now == null || user == null || now.currentId == orgId) return;
    if (!now.orgs.any((o) => o.id == orgId)) return;
    state = AsyncData(OrgsState(orgs: now.orgs, currentId: orgId));
    await _remember(user.id, orgId);
  }

  /// Which organisation an invite is for, before joining.
  Future<OrgInvitePreview> previewInvite(String code) =>
      _api(ref.read(currentUserProvider).requireValue!.id).previewInvite(code);

  /// Joins with an invite and switches to that organisation.
  Future<Org> join(String code) async {
    final user = ref.read(currentUserProvider).requireValue!;
    final api = _api(user.id);
    final joined = await api.acceptInvite(code);
    final orgs = await api.mine();
    state = AsyncData(OrgsState(orgs: orgs, currentId: joined.id));
    await _remember(user.id, joined.id);
    return joined;
  }

  /// Invite links, for an organisation's owners and admins.
  OrgsApi get api => _api(ref.read(currentUserProvider).requireValue!.id);
}

final orgsProvider = AsyncNotifierProvider<OrgsController, OrgsState>(OrgsController.new);

/// The organisation the app is showing (its id), or null before it's known
/// or with a server from before organisations. Only this id is watched by
/// the API client, so a renamed org or a new logo doesn't reload everything.
final currentOrgIdProvider = Provider<int?>((ref) => ref.watch(orgsProvider.select((orgs) => orgs.value?.currentId)));
