import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geo_kit/geo_kit.dart';
import 'package:shared_media/shared_media.dart';

import '../data/services/api_service.dart';
import '../geo/geo_services.dart';
import '../profile/user_avatar.dart';
import 'communities_api.dart';
import 'communities_providers.dart';
import 'community.dart';
import 'community_screen.dart';

/// Creating a community, or (its owner) editing one: photo, name,
/// description, public or private, and where it's based (an area, for
/// "near me"; optional). The photo uploads as soon as it's picked.
class EditCommunityScreen extends ConsumerStatefulWidget {
  const EditCommunityScreen({super.key, this.community});

  /// Null when creating.
  final Community? community;

  static Future<void> create(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const EditCommunityScreen()));

  static Future<void> edit(BuildContext context, Community community) => Navigator.of(context)
      .push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => EditCommunityScreen(community: community)));

  /// The server's limits (communityService.ts), checked here first.
  static const minNameLength = 3;
  static const maxNameLength = 60;
  static const maxDescriptionLength = 500;

  @override
  ConsumerState<EditCommunityScreen> createState() => _EditCommunityScreenState();
}

class _EditCommunityScreenState extends ConsumerState<EditCommunityScreen> {
  late final _name = TextEditingController(text: widget.community?.name ?? '');
  late final _description = TextEditingController(text: widget.community?.description ?? '');
  late var _visibility = widget.community?.visibility ?? CommunityVisibility.public;
  late Place? _area = widget.community?.area;

  Uint8List? _pickedBytes;
  Future<int>? _upload;
  bool _removePhoto = false;
  bool _saving = false;
  String? _error;

  bool get _creating => widget.community == null;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picked = await ref.read(mediaPickerProvider).pickPhoto();
    if (picked == null || !mounted) return;
    final problem = MediaLimits.problemWith(picked);
    if (problem != null) return setState(() => _error = problem);
    setState(() {
      _pickedBytes = picked.bytes;
      _removePhoto = false;
      _error = null;
      _upload = ref.read(mediaUploadServiceProvider).upload(picked).then((uploaded) => uploaded.id);
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.characters.length < EditCommunityScreen.minNameLength) {
      return setState(() => _error = 'Give it a name of at least ${EditCommunityScreen.minNameLength} characters.');
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final api = ref.read(communitiesApiProvider);
    try {
      final photoId = await _upload;
      final community = widget.community;
      final saved = community == null
          ? await api.create(
              name: name,
              description: _description.text,
              visibility: _visibility,
              photoMediaId: photoId,
              area: _area,
            )
          : await api.update(
              community.id,
              name: name,
              description: _description.text,
              visibility: _visibility,
              photoMediaId: photoId,
              removePhoto: _removePhoto,
              area: _area,
              removeArea: _area == null && community.area != null,
            );
      ref.invalidate(joinedCommunitiesProvider);
      ref.invalidate(discoverCommunitiesProvider);
      if (!mounted) return;
      if (community == null) {
        // Straight into the new community.
        Navigator.of(context).pop();
        await CommunityScreen.open(context, saved.id);
      } else {
        ref.read(communityProvider(community.id).notifier).show(saved);
        Navigator.of(context).pop();
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.isRateLimited ? 'Too many changes for now. Try again in a minute.' : _reason(e));
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Couldn\'t save. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickArea() async {
    final area = await pickPlace(
      context,
      search: ref.read(placeSearchProvider),
      tiles: ref.read(mapTilesProvider),
      location: ref.read(locationSourceProvider),
      initial: _area,
      areaOnly: true,
      title: 'Where is it based?',
    );
    if (area != null && mounted) setState(() => _area = area);
  }

  static String _reason(ApiException e) {
    try {
      return (jsonDecode(e.body) as Map<String, dynamic>)['error'] as String? ?? 'Couldn\'t save (${e.statusCode}).';
    } on Object {
      return 'Couldn\'t save (${e.statusCode}).';
    }
  }

  @override
  Widget build(BuildContext context) {
    final picked = _pickedBytes;
    final existing = _removePhoto ? null : widget.community?.photo;
    final hasPhoto = picked != null || existing != null;
    final shownName = _name.text.trim().isEmpty ? '?' : _name.text.trim();

    return Scaffold(
      appBar: AppBar(
        title: Text(_creating ? 'New community' : 'Edit community'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_creating ? 'Create' : 'Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: picked != null
                ? ClipOval(child: Image.memory(picked, width: 96, height: 96, fit: BoxFit.cover))
                : UserAvatar(name: shownName, photo: existing, radius: 48),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(onPressed: _saving ? null : _pickPhoto, child: Text(hasPhoto ? 'Change photo' : 'Add photo')),
              if (hasPhoto)
                TextButton(
                  onPressed: _saving
                      ? null
                      : () => setState(() {
                            _pickedBytes = null;
                            _upload = null;
                            _removePhoto = true;
                          }),
                  child: const Text('Remove'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            maxLength: EditCommunityScreen.maxNameLength,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            maxLength: EditCommunityScreen.maxDescriptionLength,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'What\'s it about?',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<CommunityVisibility>(
            segments: const [
              ButtonSegment(value: CommunityVisibility.public, icon: Icon(Icons.public), label: Text('Public')),
              ButtonSegment(value: CommunityVisibility.private, icon: Icon(Icons.lock_outline), label: Text('Private')),
            ],
            selected: {_visibility},
            onSelectionChanged: (selection) => setState(() => _visibility = selection.first),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _visibility == CommunityVisibility.public
                  ? 'Anyone can find it and join straight away.'
                  : 'Anyone can find it; people ask to join and a moderator lets them in.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.place_outlined),
            title: Text(_area?.name ?? 'Where it\'s based (optional)'),
            subtitle: Text(
              _area == null
                  ? 'An area helps people nearby find it. Leave it empty for an online-only community.'
                  : 'Shown to everyone, to about a kilometre.',
            ),
            trailing: _area == null
                ? null
                : IconButton(tooltip: 'Remove area', icon: const Icon(Icons.close), onPressed: () => setState(() => _area = null)),
            onTap: _saving ? null : _pickArea,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ],
      ),
    );
  }
}
