// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_database.dart';

// ignore_for_file: type=lint
class $ChatMessagesTable extends ChatMessages
    with TableInfo<$ChatMessagesTable, StoredMessage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChatMessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _conversationIdMeta = const VerificationMeta(
    'conversationId',
  );
  @override
  late final GeneratedColumn<int> conversationId = GeneratedColumn<int>(
    'conversation_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _seqMeta = const VerificationMeta('seq');
  @override
  late final GeneratedColumn<int> seq = GeneratedColumn<int>(
    'seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _messageIdMeta = const VerificationMeta(
    'messageId',
  );
  @override
  late final GeneratedColumn<int> messageId = GeneratedColumn<int>(
    'message_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
    'json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta(
    'fetchedAt',
  );
  @override
  late final GeneratedColumn<int> fetchedAt = GeneratedColumn<int>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    conversationId,
    seq,
    messageId,
    body,
    createdAt,
    json,
    fetchedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chat_messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<StoredMessage> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(
          data['conversation_id']!,
          _conversationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('seq')) {
      context.handle(
        _seqMeta,
        seq.isAcceptableOrUnknown(data['seq']!, _seqMeta),
      );
    } else if (isInserting) {
      context.missing(_seqMeta);
    }
    if (data.containsKey('message_id')) {
      context.handle(
        _messageIdMeta,
        messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_messageIdMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('json')) {
      context.handle(
        _jsonMeta,
        json.isAcceptableOrUnknown(data['json']!, _jsonMeta),
      );
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {conversationId, seq};
  @override
  StoredMessage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredMessage(
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}conversation_id'],
      )!,
      seq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}seq'],
      )!,
      messageId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}message_id'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      json: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}json'],
      )!,
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fetched_at'],
      )!,
    );
  }

  @override
  $ChatMessagesTable createAlias(String alias) {
    return $ChatMessagesTable(attachedDatabase, alias);
  }
}

class StoredMessage extends DataClass implements Insertable<StoredMessage> {
  final int conversationId;

  /// Its place in the conversation: 1, 2, 3, ... (the server's seq).
  final int seq;

  /// The server's id for it.
  final int messageId;

  /// The text, for search.
  final String body;
  final int createdAt;

  /// The whole message as the server sent it.
  final String json;

  /// When this copy came from the server (photo links in [json] expire).
  final int fetchedAt;
  const StoredMessage({
    required this.conversationId,
    required this.seq,
    required this.messageId,
    required this.body,
    required this.createdAt,
    required this.json,
    required this.fetchedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['conversation_id'] = Variable<int>(conversationId);
    map['seq'] = Variable<int>(seq);
    map['message_id'] = Variable<int>(messageId);
    map['body'] = Variable<String>(body);
    map['created_at'] = Variable<int>(createdAt);
    map['json'] = Variable<String>(json);
    map['fetched_at'] = Variable<int>(fetchedAt);
    return map;
  }

  ChatMessagesCompanion toCompanion(bool nullToAbsent) {
    return ChatMessagesCompanion(
      conversationId: Value(conversationId),
      seq: Value(seq),
      messageId: Value(messageId),
      body: Value(body),
      createdAt: Value(createdAt),
      json: Value(json),
      fetchedAt: Value(fetchedAt),
    );
  }

  factory StoredMessage.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredMessage(
      conversationId: serializer.fromJson<int>(json['conversationId']),
      seq: serializer.fromJson<int>(json['seq']),
      messageId: serializer.fromJson<int>(json['messageId']),
      body: serializer.fromJson<String>(json['body']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      json: serializer.fromJson<String>(json['json']),
      fetchedAt: serializer.fromJson<int>(json['fetchedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'conversationId': serializer.toJson<int>(conversationId),
      'seq': serializer.toJson<int>(seq),
      'messageId': serializer.toJson<int>(messageId),
      'body': serializer.toJson<String>(body),
      'createdAt': serializer.toJson<int>(createdAt),
      'json': serializer.toJson<String>(json),
      'fetchedAt': serializer.toJson<int>(fetchedAt),
    };
  }

  StoredMessage copyWith({
    int? conversationId,
    int? seq,
    int? messageId,
    String? body,
    int? createdAt,
    String? json,
    int? fetchedAt,
  }) => StoredMessage(
    conversationId: conversationId ?? this.conversationId,
    seq: seq ?? this.seq,
    messageId: messageId ?? this.messageId,
    body: body ?? this.body,
    createdAt: createdAt ?? this.createdAt,
    json: json ?? this.json,
    fetchedAt: fetchedAt ?? this.fetchedAt,
  );
  StoredMessage copyWithCompanion(ChatMessagesCompanion data) {
    return StoredMessage(
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      seq: data.seq.present ? data.seq.value : this.seq,
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
      body: data.body.present ? data.body.value : this.body,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      json: data.json.present ? data.json.value : this.json,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredMessage(')
          ..write('conversationId: $conversationId, ')
          ..write('seq: $seq, ')
          ..write('messageId: $messageId, ')
          ..write('body: $body, ')
          ..write('createdAt: $createdAt, ')
          ..write('json: $json, ')
          ..write('fetchedAt: $fetchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    conversationId,
    seq,
    messageId,
    body,
    createdAt,
    json,
    fetchedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredMessage &&
          other.conversationId == this.conversationId &&
          other.seq == this.seq &&
          other.messageId == this.messageId &&
          other.body == this.body &&
          other.createdAt == this.createdAt &&
          other.json == this.json &&
          other.fetchedAt == this.fetchedAt);
}

class ChatMessagesCompanion extends UpdateCompanion<StoredMessage> {
  final Value<int> conversationId;
  final Value<int> seq;
  final Value<int> messageId;
  final Value<String> body;
  final Value<int> createdAt;
  final Value<String> json;
  final Value<int> fetchedAt;
  final Value<int> rowid;
  const ChatMessagesCompanion({
    this.conversationId = const Value.absent(),
    this.seq = const Value.absent(),
    this.messageId = const Value.absent(),
    this.body = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.json = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChatMessagesCompanion.insert({
    required int conversationId,
    required int seq,
    required int messageId,
    required String body,
    required int createdAt,
    required String json,
    required int fetchedAt,
    this.rowid = const Value.absent(),
  }) : conversationId = Value(conversationId),
       seq = Value(seq),
       messageId = Value(messageId),
       body = Value(body),
       createdAt = Value(createdAt),
       json = Value(json),
       fetchedAt = Value(fetchedAt);
  static Insertable<StoredMessage> custom({
    Expression<int>? conversationId,
    Expression<int>? seq,
    Expression<int>? messageId,
    Expression<String>? body,
    Expression<int>? createdAt,
    Expression<String>? json,
    Expression<int>? fetchedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (conversationId != null) 'conversation_id': conversationId,
      if (seq != null) 'seq': seq,
      if (messageId != null) 'message_id': messageId,
      if (body != null) 'body': body,
      if (createdAt != null) 'created_at': createdAt,
      if (json != null) 'json': json,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChatMessagesCompanion copyWith({
    Value<int>? conversationId,
    Value<int>? seq,
    Value<int>? messageId,
    Value<String>? body,
    Value<int>? createdAt,
    Value<String>? json,
    Value<int>? fetchedAt,
    Value<int>? rowid,
  }) {
    return ChatMessagesCompanion(
      conversationId: conversationId ?? this.conversationId,
      seq: seq ?? this.seq,
      messageId: messageId ?? this.messageId,
      body: body ?? this.body,
      createdAt: createdAt ?? this.createdAt,
      json: json ?? this.json,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (conversationId.present) {
      map['conversation_id'] = Variable<int>(conversationId.value);
    }
    if (seq.present) {
      map['seq'] = Variable<int>(seq.value);
    }
    if (messageId.present) {
      map['message_id'] = Variable<int>(messageId.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<int>(fetchedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChatMessagesCompanion(')
          ..write('conversationId: $conversationId, ')
          ..write('seq: $seq, ')
          ..write('messageId: $messageId, ')
          ..write('body: $body, ')
          ..write('createdAt: $createdAt, ')
          ..write('json: $json, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncedRangesTable extends SyncedRanges
    with TableInfo<$SyncedRangesTable, SyncedRange> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncedRangesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _conversationIdMeta = const VerificationMeta(
    'conversationId',
  );
  @override
  late final GeneratedColumn<int> conversationId = GeneratedColumn<int>(
    'conversation_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lowSeqMeta = const VerificationMeta('lowSeq');
  @override
  late final GeneratedColumn<int> lowSeq = GeneratedColumn<int>(
    'low_seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _highSeqMeta = const VerificationMeta(
    'highSeq',
  );
  @override
  late final GeneratedColumn<int> highSeq = GeneratedColumn<int>(
    'high_seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [conversationId, lowSeq, highSeq];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'synced_ranges';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncedRange> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(
          data['conversation_id']!,
          _conversationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('low_seq')) {
      context.handle(
        _lowSeqMeta,
        lowSeq.isAcceptableOrUnknown(data['low_seq']!, _lowSeqMeta),
      );
    } else if (isInserting) {
      context.missing(_lowSeqMeta);
    }
    if (data.containsKey('high_seq')) {
      context.handle(
        _highSeqMeta,
        highSeq.isAcceptableOrUnknown(data['high_seq']!, _highSeqMeta),
      );
    } else if (isInserting) {
      context.missing(_highSeqMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {conversationId, lowSeq};
  @override
  SyncedRange map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncedRange(
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}conversation_id'],
      )!,
      lowSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}low_seq'],
      )!,
      highSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}high_seq'],
      )!,
    );
  }

  @override
  $SyncedRangesTable createAlias(String alias) {
    return $SyncedRangesTable(attachedDatabase, alias);
  }
}

class SyncedRange extends DataClass implements Insertable<SyncedRange> {
  final int conversationId;
  final int lowSeq;
  final int highSeq;
  const SyncedRange({
    required this.conversationId,
    required this.lowSeq,
    required this.highSeq,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['conversation_id'] = Variable<int>(conversationId);
    map['low_seq'] = Variable<int>(lowSeq);
    map['high_seq'] = Variable<int>(highSeq);
    return map;
  }

  SyncedRangesCompanion toCompanion(bool nullToAbsent) {
    return SyncedRangesCompanion(
      conversationId: Value(conversationId),
      lowSeq: Value(lowSeq),
      highSeq: Value(highSeq),
    );
  }

  factory SyncedRange.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncedRange(
      conversationId: serializer.fromJson<int>(json['conversationId']),
      lowSeq: serializer.fromJson<int>(json['lowSeq']),
      highSeq: serializer.fromJson<int>(json['highSeq']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'conversationId': serializer.toJson<int>(conversationId),
      'lowSeq': serializer.toJson<int>(lowSeq),
      'highSeq': serializer.toJson<int>(highSeq),
    };
  }

  SyncedRange copyWith({int? conversationId, int? lowSeq, int? highSeq}) =>
      SyncedRange(
        conversationId: conversationId ?? this.conversationId,
        lowSeq: lowSeq ?? this.lowSeq,
        highSeq: highSeq ?? this.highSeq,
      );
  SyncedRange copyWithCompanion(SyncedRangesCompanion data) {
    return SyncedRange(
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      lowSeq: data.lowSeq.present ? data.lowSeq.value : this.lowSeq,
      highSeq: data.highSeq.present ? data.highSeq.value : this.highSeq,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncedRange(')
          ..write('conversationId: $conversationId, ')
          ..write('lowSeq: $lowSeq, ')
          ..write('highSeq: $highSeq')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(conversationId, lowSeq, highSeq);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncedRange &&
          other.conversationId == this.conversationId &&
          other.lowSeq == this.lowSeq &&
          other.highSeq == this.highSeq);
}

class SyncedRangesCompanion extends UpdateCompanion<SyncedRange> {
  final Value<int> conversationId;
  final Value<int> lowSeq;
  final Value<int> highSeq;
  final Value<int> rowid;
  const SyncedRangesCompanion({
    this.conversationId = const Value.absent(),
    this.lowSeq = const Value.absent(),
    this.highSeq = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncedRangesCompanion.insert({
    required int conversationId,
    required int lowSeq,
    required int highSeq,
    this.rowid = const Value.absent(),
  }) : conversationId = Value(conversationId),
       lowSeq = Value(lowSeq),
       highSeq = Value(highSeq);
  static Insertable<SyncedRange> custom({
    Expression<int>? conversationId,
    Expression<int>? lowSeq,
    Expression<int>? highSeq,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (conversationId != null) 'conversation_id': conversationId,
      if (lowSeq != null) 'low_seq': lowSeq,
      if (highSeq != null) 'high_seq': highSeq,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncedRangesCompanion copyWith({
    Value<int>? conversationId,
    Value<int>? lowSeq,
    Value<int>? highSeq,
    Value<int>? rowid,
  }) {
    return SyncedRangesCompanion(
      conversationId: conversationId ?? this.conversationId,
      lowSeq: lowSeq ?? this.lowSeq,
      highSeq: highSeq ?? this.highSeq,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (conversationId.present) {
      map['conversation_id'] = Variable<int>(conversationId.value);
    }
    if (lowSeq.present) {
      map['low_seq'] = Variable<int>(lowSeq.value);
    }
    if (highSeq.present) {
      map['high_seq'] = Variable<int>(highSeq.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncedRangesCompanion(')
          ..write('conversationId: $conversationId, ')
          ..write('lowSeq: $lowSeq, ')
          ..write('highSeq: $highSeq, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DeviceBlobsTable extends DeviceBlobs
    with TableInfo<$DeviceBlobsTable, DeviceBlob> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DeviceBlobsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<Uint8List> value = GeneratedColumn<Uint8List>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [name, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'device_blobs';
  @override
  VerificationContext validateIntegrity(
    Insertable<DeviceBlob> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {name};
  @override
  DeviceBlob map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DeviceBlob(
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $DeviceBlobsTable createAlias(String alias) {
    return $DeviceBlobsTable(attachedDatabase, alias);
  }
}

class DeviceBlob extends DataClass implements Insertable<DeviceBlob> {
  final String name;
  final Uint8List value;
  const DeviceBlob({required this.name, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['name'] = Variable<String>(name);
    map['value'] = Variable<Uint8List>(value);
    return map;
  }

  DeviceBlobsCompanion toCompanion(bool nullToAbsent) {
    return DeviceBlobsCompanion(name: Value(name), value: Value(value));
  }

  factory DeviceBlob.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DeviceBlob(
      name: serializer.fromJson<String>(json['name']),
      value: serializer.fromJson<Uint8List>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'name': serializer.toJson<String>(name),
      'value': serializer.toJson<Uint8List>(value),
    };
  }

  DeviceBlob copyWith({String? name, Uint8List? value}) =>
      DeviceBlob(name: name ?? this.name, value: value ?? this.value);
  DeviceBlob copyWithCompanion(DeviceBlobsCompanion data) {
    return DeviceBlob(
      name: data.name.present ? data.name.value : this.name,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DeviceBlob(')
          ..write('name: $name, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(name, $driftBlobEquality.hash(value));
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DeviceBlob &&
          other.name == this.name &&
          $driftBlobEquality.equals(other.value, this.value));
}

class DeviceBlobsCompanion extends UpdateCompanion<DeviceBlob> {
  final Value<String> name;
  final Value<Uint8List> value;
  final Value<int> rowid;
  const DeviceBlobsCompanion({
    this.name = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DeviceBlobsCompanion.insert({
    required String name,
    required Uint8List value,
    this.rowid = const Value.absent(),
  }) : name = Value(name),
       value = Value(value);
  static Insertable<DeviceBlob> custom({
    Expression<String>? name,
    Expression<Uint8List>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (name != null) 'name': name,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DeviceBlobsCompanion copyWith({
    Value<String>? name,
    Value<Uint8List>? value,
    Value<int>? rowid,
  }) {
    return DeviceBlobsCompanion(
      name: name ?? this.name,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (value.present) {
      map['value'] = Variable<Uint8List>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DeviceBlobsCompanion(')
          ..write('name: $name, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$ChatDatabase extends GeneratedDatabase {
  _$ChatDatabase(QueryExecutor e) : super(e);
  $ChatDatabaseManager get managers => $ChatDatabaseManager(this);
  late final $ChatMessagesTable chatMessages = $ChatMessagesTable(this);
  late final $SyncedRangesTable syncedRanges = $SyncedRangesTable(this);
  late final $DeviceBlobsTable deviceBlobs = $DeviceBlobsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    chatMessages,
    syncedRanges,
    deviceBlobs,
  ];
}

typedef $$ChatMessagesTableCreateCompanionBuilder =
    ChatMessagesCompanion Function({
      required int conversationId,
      required int seq,
      required int messageId,
      required String body,
      required int createdAt,
      required String json,
      required int fetchedAt,
      Value<int> rowid,
    });
typedef $$ChatMessagesTableUpdateCompanionBuilder =
    ChatMessagesCompanion Function({
      Value<int> conversationId,
      Value<int> seq,
      Value<int> messageId,
      Value<String> body,
      Value<int> createdAt,
      Value<String> json,
      Value<int> fetchedAt,
      Value<int> rowid,
    });

class $$ChatMessagesTableFilterComposer
    extends Composer<_$ChatDatabase, $ChatMessagesTable> {
  $$ChatMessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get seq => $composableBuilder(
    column: $table.seq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ChatMessagesTableOrderingComposer
    extends Composer<_$ChatDatabase, $ChatMessagesTable> {
  $$ChatMessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get seq => $composableBuilder(
    column: $table.seq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ChatMessagesTableAnnotationComposer
    extends Composer<_$ChatDatabase, $ChatMessagesTable> {
  $$ChatMessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get seq =>
      $composableBuilder(column: $table.seq, builder: (column) => column);

  GeneratedColumn<int> get messageId =>
      $composableBuilder(column: $table.messageId, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);

  GeneratedColumn<int> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);
}

class $$ChatMessagesTableTableManager
    extends
        RootTableManager<
          _$ChatDatabase,
          $ChatMessagesTable,
          StoredMessage,
          $$ChatMessagesTableFilterComposer,
          $$ChatMessagesTableOrderingComposer,
          $$ChatMessagesTableAnnotationComposer,
          $$ChatMessagesTableCreateCompanionBuilder,
          $$ChatMessagesTableUpdateCompanionBuilder,
          (
            StoredMessage,
            BaseReferences<_$ChatDatabase, $ChatMessagesTable, StoredMessage>,
          ),
          StoredMessage,
          PrefetchHooks Function()
        > {
  $$ChatMessagesTableTableManager(_$ChatDatabase db, $ChatMessagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChatMessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChatMessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChatMessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> conversationId = const Value.absent(),
                Value<int> seq = const Value.absent(),
                Value<int> messageId = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<String> json = const Value.absent(),
                Value<int> fetchedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChatMessagesCompanion(
                conversationId: conversationId,
                seq: seq,
                messageId: messageId,
                body: body,
                createdAt: createdAt,
                json: json,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int conversationId,
                required int seq,
                required int messageId,
                required String body,
                required int createdAt,
                required String json,
                required int fetchedAt,
                Value<int> rowid = const Value.absent(),
              }) => ChatMessagesCompanion.insert(
                conversationId: conversationId,
                seq: seq,
                messageId: messageId,
                body: body,
                createdAt: createdAt,
                json: json,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ChatMessagesTable, StoredMessage>(table),
                  BaseReferences<
                    _$ChatDatabase,
                    $ChatMessagesTable,
                    StoredMessage
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ChatMessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$ChatDatabase,
      $ChatMessagesTable,
      StoredMessage,
      $$ChatMessagesTableFilterComposer,
      $$ChatMessagesTableOrderingComposer,
      $$ChatMessagesTableAnnotationComposer,
      $$ChatMessagesTableCreateCompanionBuilder,
      $$ChatMessagesTableUpdateCompanionBuilder,
      (
        StoredMessage,
        BaseReferences<_$ChatDatabase, $ChatMessagesTable, StoredMessage>,
      ),
      StoredMessage,
      PrefetchHooks Function()
    >;
typedef $$SyncedRangesTableCreateCompanionBuilder =
    SyncedRangesCompanion Function({
      required int conversationId,
      required int lowSeq,
      required int highSeq,
      Value<int> rowid,
    });
typedef $$SyncedRangesTableUpdateCompanionBuilder =
    SyncedRangesCompanion Function({
      Value<int> conversationId,
      Value<int> lowSeq,
      Value<int> highSeq,
      Value<int> rowid,
    });

class $$SyncedRangesTableFilterComposer
    extends Composer<_$ChatDatabase, $SyncedRangesTable> {
  $$SyncedRangesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lowSeq => $composableBuilder(
    column: $table.lowSeq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get highSeq => $composableBuilder(
    column: $table.highSeq,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncedRangesTableOrderingComposer
    extends Composer<_$ChatDatabase, $SyncedRangesTable> {
  $$SyncedRangesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lowSeq => $composableBuilder(
    column: $table.lowSeq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get highSeq => $composableBuilder(
    column: $table.highSeq,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncedRangesTableAnnotationComposer
    extends Composer<_$ChatDatabase, $SyncedRangesTable> {
  $$SyncedRangesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lowSeq =>
      $composableBuilder(column: $table.lowSeq, builder: (column) => column);

  GeneratedColumn<int> get highSeq =>
      $composableBuilder(column: $table.highSeq, builder: (column) => column);
}

class $$SyncedRangesTableTableManager
    extends
        RootTableManager<
          _$ChatDatabase,
          $SyncedRangesTable,
          SyncedRange,
          $$SyncedRangesTableFilterComposer,
          $$SyncedRangesTableOrderingComposer,
          $$SyncedRangesTableAnnotationComposer,
          $$SyncedRangesTableCreateCompanionBuilder,
          $$SyncedRangesTableUpdateCompanionBuilder,
          (
            SyncedRange,
            BaseReferences<_$ChatDatabase, $SyncedRangesTable, SyncedRange>,
          ),
          SyncedRange,
          PrefetchHooks Function()
        > {
  $$SyncedRangesTableTableManager(_$ChatDatabase db, $SyncedRangesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncedRangesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncedRangesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncedRangesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> conversationId = const Value.absent(),
                Value<int> lowSeq = const Value.absent(),
                Value<int> highSeq = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncedRangesCompanion(
                conversationId: conversationId,
                lowSeq: lowSeq,
                highSeq: highSeq,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int conversationId,
                required int lowSeq,
                required int highSeq,
                Value<int> rowid = const Value.absent(),
              }) => SyncedRangesCompanion.insert(
                conversationId: conversationId,
                lowSeq: lowSeq,
                highSeq: highSeq,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SyncedRangesTable, SyncedRange>(table),
                  BaseReferences<
                    _$ChatDatabase,
                    $SyncedRangesTable,
                    SyncedRange
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncedRangesTableProcessedTableManager =
    ProcessedTableManager<
      _$ChatDatabase,
      $SyncedRangesTable,
      SyncedRange,
      $$SyncedRangesTableFilterComposer,
      $$SyncedRangesTableOrderingComposer,
      $$SyncedRangesTableAnnotationComposer,
      $$SyncedRangesTableCreateCompanionBuilder,
      $$SyncedRangesTableUpdateCompanionBuilder,
      (
        SyncedRange,
        BaseReferences<_$ChatDatabase, $SyncedRangesTable, SyncedRange>,
      ),
      SyncedRange,
      PrefetchHooks Function()
    >;
typedef $$DeviceBlobsTableCreateCompanionBuilder =
    DeviceBlobsCompanion Function({
      required String name,
      required Uint8List value,
      Value<int> rowid,
    });
typedef $$DeviceBlobsTableUpdateCompanionBuilder =
    DeviceBlobsCompanion Function({
      Value<String> name,
      Value<Uint8List> value,
      Value<int> rowid,
    });

class $$DeviceBlobsTableFilterComposer
    extends Composer<_$ChatDatabase, $DeviceBlobsTable> {
  $$DeviceBlobsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DeviceBlobsTableOrderingComposer
    extends Composer<_$ChatDatabase, $DeviceBlobsTable> {
  $$DeviceBlobsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DeviceBlobsTableAnnotationComposer
    extends Composer<_$ChatDatabase, $DeviceBlobsTable> {
  $$DeviceBlobsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<Uint8List> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$DeviceBlobsTableTableManager
    extends
        RootTableManager<
          _$ChatDatabase,
          $DeviceBlobsTable,
          DeviceBlob,
          $$DeviceBlobsTableFilterComposer,
          $$DeviceBlobsTableOrderingComposer,
          $$DeviceBlobsTableAnnotationComposer,
          $$DeviceBlobsTableCreateCompanionBuilder,
          $$DeviceBlobsTableUpdateCompanionBuilder,
          (
            DeviceBlob,
            BaseReferences<_$ChatDatabase, $DeviceBlobsTable, DeviceBlob>,
          ),
          DeviceBlob,
          PrefetchHooks Function()
        > {
  $$DeviceBlobsTableTableManager(_$ChatDatabase db, $DeviceBlobsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DeviceBlobsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DeviceBlobsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DeviceBlobsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> name = const Value.absent(),
            Value<Uint8List> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => DeviceBlobsCompanion(name: name, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String name,
                required Uint8List value,
                Value<int> rowid = const Value.absent(),
              }) => DeviceBlobsCompanion.insert(
                name: name,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DeviceBlobsTable, DeviceBlob>(table),
                  BaseReferences<_$ChatDatabase, $DeviceBlobsTable, DeviceBlob>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DeviceBlobsTableProcessedTableManager =
    ProcessedTableManager<
      _$ChatDatabase,
      $DeviceBlobsTable,
      DeviceBlob,
      $$DeviceBlobsTableFilterComposer,
      $$DeviceBlobsTableOrderingComposer,
      $$DeviceBlobsTableAnnotationComposer,
      $$DeviceBlobsTableCreateCompanionBuilder,
      $$DeviceBlobsTableUpdateCompanionBuilder,
      (
        DeviceBlob,
        BaseReferences<_$ChatDatabase, $DeviceBlobsTable, DeviceBlob>,
      ),
      DeviceBlob,
      PrefetchHooks Function()
    >;

class $ChatDatabaseManager {
  final _$ChatDatabase _db;
  $ChatDatabaseManager(this._db);
  $$ChatMessagesTableTableManager get chatMessages =>
      $$ChatMessagesTableTableManager(_db, _db.chatMessages);
  $$SyncedRangesTableTableManager get syncedRanges =>
      $$SyncedRangesTableTableManager(_db, _db.syncedRanges);
  $$DeviceBlobsTableTableManager get deviceBlobs =>
      $$DeviceBlobsTableTableManager(_db, _db.deviceBlobs);
}
