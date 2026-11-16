import 'dart:convert';

import 'package:app_core/models/models.dart';
import 'package:flutter/foundation.dart';
import 'package:geo_kit/geo_kit.dart';

/// A location shared in a chat, like WhatsApp's: a spot (your current
/// location, or a place you picked) or a live share that moves for 15
/// minutes, an hour or 8 hours.
///
/// Where it comes from: a normal chat's message has it from the server
/// (`location`); an encrypted chat's message has it inside the
/// ciphertext, and is stored with it once decrypted (see E2eChats).
@immutable
class ChatLocation {
  const ChatLocation({required this.point, this.name, this.address, this.liveUntil, this.stoppedAt, this.liveKey});

  final GeoPoint point;
  final String? name;
  final String? address;

  /// A live share: until when it runs (null: a fixed spot).
  final DateTime? liveUntil;

  /// When the sharer stopped it early (normal chats; encrypted ones send a
  /// "location_stop" message instead).
  final DateTime? stoppedAt;

  /// Encrypted chats' live shares: the key its moving positions are sealed
  /// with (see LiveUpdateSealer). Only ever inside the encrypted message.
  final List<int>? liveKey;

  bool get isLive => liveUntil != null;

  /// Still running at [now] (as far as this message says).
  bool runningAt(DateTime now) => isLive && stoppedAt == null && liveUntil!.isAfter(now);

  /// "Sector 18 Market", or "Shared location".
  String get title => name ?? (isLive ? 'Live location' : 'Shared location');

  /// [message]'s location, if it shares one.
  static ChatLocation? of(ChatMessage message) {
    final json = message.json['location'];
    if (json is! Map) return null;
    final live = json['live'];
    DateTime? time(Object? ms) => ms is int ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
    final key = live is Map ? live['key'] : null;
    return ChatLocation(
      point: GeoPoint((json['lat'] as num).toDouble(), (json['lng'] as num).toDouble()),
      name: json['name'] as String?,
      address: json['address'] as String?,
      liveUntil: live is Map ? time(live['until']) : null,
      stoppedAt: live is Map ? time(live['stoppedAt']) : null,
      liveKey: key is String ? base64Decode(key) : null,
    );
  }

  /// The live share [message] says has ended (an encrypted chat's stop), if it's one.
  static int? stopOf(ChatMessage message) => message.json['location_stop'] as int?;
}

/// "47 min left", "2 h 5 min left".
String timeLeft(Duration left) {
  final minutes = left.inSeconds <= 0 ? 0 : (left.inSeconds / 60).ceil();
  if (minutes < 60) return '$minutes min left';
  final rest = minutes % 60;
  return rest == 0 ? '${minutes ~/ 60} h left' : '${minutes ~/ 60} h $rest min left';
}
