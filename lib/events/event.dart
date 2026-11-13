import 'package:intl/intl.dart';

import '../models/models.dart';

enum EventLocationKind { inPerson, online }

enum RsvpStatus { going, waitlist }

/// An event as the signed-in user sees it.
class Event {
  const Event({
    required this.id,
    required this.communityId,
    required this.communityName,
    required this.title,
    required this.startsAt,
    required this.endsAt,
    required this.timeZone,
    required this.utcOffsetMinutes,
    required this.locationKind,
    required this.goingCount,
    required this.waitlistCount,
    this.description,
    this.placeName,
    this.address,
    this.latitude,
    this.longitude,
    this.onlineUrl,
    this.capacity,
    this.spotsLeft,
    this.cover,
    this.cancelled = false,
    this.past = false,
    this.myRsvp,
    this.myWaitlistPosition,
    this.canManage = false,
    this.canRsvp = false,
  });

  factory Event.fromJson(Map<String, dynamic> json) {
    final location = json['location'] as Map<String, dynamic>;
    final community = json['community'] as Map<String, dynamic>;
    return Event(
      id: json['id'] as int,
      communityId: community['id'] as int,
      communityName: community['name'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      startsAt: DateTime.fromMillisecondsSinceEpoch(json['startsAt'] as int, isUtc: true),
      endsAt: DateTime.fromMillisecondsSinceEpoch(json['endsAt'] as int, isUtc: true),
      timeZone: json['timeZone'] as String,
      utcOffsetMinutes: json['utcOffsetMinutes'] as int? ?? 0,
      locationKind: location['kind'] == 'online' ? EventLocationKind.online : EventLocationKind.inPerson,
      placeName: location['placeName'] as String?,
      address: location['address'] as String?,
      latitude: (location['latitude'] as num?)?.toDouble(),
      longitude: (location['longitude'] as num?)?.toDouble(),
      onlineUrl: location['onlineUrl'] as String?,
      capacity: json['capacity'] as int?,
      goingCount: json['goingCount'] as int? ?? 0,
      waitlistCount: json['waitlistCount'] as int? ?? 0,
      spotsLeft: json['spotsLeft'] as int?,
      cover: ProfilePhoto.fromJson(json['cover']),
      cancelled: json['cancelled'] as bool? ?? false,
      past: json['past'] as bool? ?? false,
      myRsvp: switch (json['myRsvp']) {
        'going' => RsvpStatus.going,
        'waitlist' => RsvpStatus.waitlist,
        _ => null,
      },
      myWaitlistPosition: json['myWaitlistPosition'] as int?,
      canManage: json['canManage'] as bool? ?? false,
      canRsvp: json['canRsvp'] as bool? ?? false,
    );
  }

  final int id;
  final int communityId;
  final String communityName;
  final String title;
  final String? description;

  /// In UTC; see [localStart] and [eventClockStart] for showing them.
  final DateTime startsAt;
  final DateTime endsAt;

  /// Where the event's own clock is, e.g. Asia/Kolkata.
  final String timeZone;

  /// The event's offset from UTC (at its start), so its own clock can be
  /// shown without a time zone database.
  final int utcOffsetMinutes;
  final EventLocationKind locationKind;
  final String? placeName;
  final String? address;
  final double? latitude;
  final double? longitude;

  /// Only for people going (and organisers).
  final String? onlineUrl;

  /// Null: no limit.
  final int? capacity;
  final int goingCount;
  final int waitlistCount;
  final int? spotsLeft;
  final ProfilePhoto? cover;
  final bool cancelled;
  final bool past;
  final RsvpStatus? myRsvp;
  final int? myWaitlistPosition;
  final bool canManage;
  final bool canRsvp;

  bool get isOnline => locationKind == EventLocationKind.online;
  bool get isFull => spotsLeft == 0;

  /// The start on this device's clock.
  DateTime get localStart => startsAt.toLocal();
  DateTime get localEnd => endsAt.toLocal();

  /// The start on the event's own clock (a UTC DateTime holding those wall-clock numbers).
  DateTime get eventClockStart => startsAt.add(Duration(minutes: utcOffsetMinutes));
  DateTime get eventClockEnd => endsAt.add(Duration(minutes: utcOffsetMinutes));

  /// Whether this device's clock differs from the event's at its start (a traveller, an online event abroad).
  bool get inAnotherTimeZone => localStart.timeZoneOffset.inMinutes != utcOffsetMinutes;

  /// "Sun 16 Nov · 06:00 – 08:00" on this device's clock.
  String get localWhen => _when(localStart, localEnd);

  /// The same on the event's clock: "06:00 – 08:00 Asia/Kolkata".
  String get eventWhen => '${_when(eventClockStart, eventClockEnd)} ($timeZone)';

  static String _when(DateTime start, DateTime end) {
    final day = DateFormat('EEE d MMM');
    final time = DateFormat('HH:mm');
    final sameDay = start.year == end.year && start.month == end.month && start.day == end.day;
    return sameDay
        ? '${day.format(start)} · ${time.format(start)} – ${time.format(end)}'
        : '${day.format(start)} ${time.format(start)} – ${day.format(end)} ${time.format(end)}';
  }
}

/// One person going (or waiting).
class EventAttendee {
  const EventAttendee({required this.user, required this.status});

  factory EventAttendee.fromJson(Map<String, dynamic> json) => EventAttendee(
        user: User.fromJson(json['user'] as Map<String, dynamic>),
        status: json['status'] == 'waitlist' ? RsvpStatus.waitlist : RsvpStatus.going,
      );

  final User user;
  final RsvpStatus status;
}
