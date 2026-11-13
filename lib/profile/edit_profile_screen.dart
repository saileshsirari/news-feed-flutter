import 'dart:typed_data';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_media/shared_media.dart';

import '../data/services/api_service.dart';
import '../data/services/service_providers.dart';
import '../models/models.dart';
import 'profile_notifier.dart';
import 'user_avatar.dart';

/// Edits your own profile: photo, name and bio. The photo uploads as soon
/// as it's picked (like a chat attachment), so Save is quick.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key, required this.user});

  final User user;

  static Future<void> open(BuildContext context, User user) =>
      Navigator.of(context)
          .push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => EditProfileScreen(user: user)));

  /// The server's limits (profileService.ts), checked here first.
  static const maxNameLength = 50;
  static const maxBioLength = 300;

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late final _name = TextEditingController(text: widget.user.displayName ?? '');
  late final _bio = TextEditingController(text: widget.user.bio ?? '');

  /// A newly picked photo: shown at once, uploaded meanwhile.
  Uint8List? _pickedBytes;
  Future<int>? _upload;
  bool _removePhoto = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
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
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final photoId = await _upload;
      final me = await ref
          .read(apiServiceProvider)
          .updateProfile(
            userId: widget.user.id,
            displayName: _name.text,
            bio: _bio.text,
            photoMediaId: photoId,
            removePhoto: _removePhoto,
          );
      if (!mounted) return;
      ref.read(profileProvider(widget.user.id).notifier).showEdited(me);
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted)
        setState(
          () => _error = e.isRateLimited
              ? 'Too many changes for now. Try again in a minute.'
              : 'Couldn\'t save: ${_reason(e)}',
        );
    } catch (_) {
      if (mounted) setState(() => _error = 'Couldn\'t save. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// The server's reason ("bio can be at most 300 characters"), if it gave one.
  static String _reason(ApiException e) {
    try {
      return (jsonDecode(e.body) as Map<String, dynamic>)['error'] as String? ?? 'error ${e.statusCode}';
    } on Object {
      return 'error ${e.statusCode}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final picked = _pickedBytes;
    final hasPhoto = picked != null || (!_removePhoto && widget.user.photo != null);
    final avatar = picked != null
        ? ClipOval(child: Image.memory(picked, width: 96, height: 96, fit: BoxFit.cover))
        : UserAvatar(
            name: _name.text.trim().isNotEmpty ? _name.text.trim() : widget.user.username,
            photo: _removePhoto ? null : widget.user.photo,
            radius: 48,
          );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit profile'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(child: avatar),
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
            maxLength: EditProfileScreen.maxNameLength,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Name',
              helperText: 'Shown instead of @${widget.user.username}. Leave empty to use that.',
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bio,
            maxLength: EditProfileScreen.maxBioLength,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(labelText: 'Bio', border: OutlineInputBorder()),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ],
      ),
    );
  }
}
