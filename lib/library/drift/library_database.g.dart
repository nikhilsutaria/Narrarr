// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'library_database.dart';

// ignore_for_file: type=lint
class $BooksTable extends Books with TableInfo<$BooksTable, BookRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BooksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _authorMeta = const VerificationMeta('author');
  @override
  late final GeneratedColumn<String> author = GeneratedColumn<String>(
    'author',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _filePathMeta = const VerificationMeta(
    'filePath',
  );
  @override
  late final GeneratedColumn<String> filePath = GeneratedColumn<String>(
    'file_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _coverPathMeta = const VerificationMeta(
    'coverPath',
  );
  @override
  late final GeneratedColumn<String> coverPath = GeneratedColumn<String>(
    'cover_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _addedAtMsMeta = const VerificationMeta(
    'addedAtMs',
  );
  @override
  late final GeneratedColumn<int> addedAtMs = GeneratedColumn<int>(
    'added_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastLocatorJsonMeta = const VerificationMeta(
    'lastLocatorJson',
  );
  @override
  late final GeneratedColumn<String> lastLocatorJson = GeneratedColumn<String>(
    'last_locator_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isBundledSampleMeta = const VerificationMeta(
    'isBundledSample',
  );
  @override
  late final GeneratedColumn<bool> isBundledSample = GeneratedColumn<bool>(
    'is_bundled_sample',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_bundled_sample" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    author,
    filePath,
    coverPath,
    addedAtMs,
    lastLocatorJson,
    isBundledSample,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'books';
  @override
  VerificationContext validateIntegrity(
    Insertable<BookRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('author')) {
      context.handle(
        _authorMeta,
        author.isAcceptableOrUnknown(data['author']!, _authorMeta),
      );
    }
    if (data.containsKey('file_path')) {
      context.handle(
        _filePathMeta,
        filePath.isAcceptableOrUnknown(data['file_path']!, _filePathMeta),
      );
    } else if (isInserting) {
      context.missing(_filePathMeta);
    }
    if (data.containsKey('cover_path')) {
      context.handle(
        _coverPathMeta,
        coverPath.isAcceptableOrUnknown(data['cover_path']!, _coverPathMeta),
      );
    }
    if (data.containsKey('added_at_ms')) {
      context.handle(
        _addedAtMsMeta,
        addedAtMs.isAcceptableOrUnknown(data['added_at_ms']!, _addedAtMsMeta),
      );
    }
    if (data.containsKey('last_locator_json')) {
      context.handle(
        _lastLocatorJsonMeta,
        lastLocatorJson.isAcceptableOrUnknown(
          data['last_locator_json']!,
          _lastLocatorJsonMeta,
        ),
      );
    }
    if (data.containsKey('is_bundled_sample')) {
      context.handle(
        _isBundledSampleMeta,
        isBundledSample.isAcceptableOrUnknown(
          data['is_bundled_sample']!,
          _isBundledSampleMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  BookRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BookRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      author: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}author'],
      ),
      filePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_path'],
      )!,
      coverPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_path'],
      ),
      addedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}added_at_ms'],
      )!,
      lastLocatorJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_locator_json'],
      ),
      isBundledSample: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_bundled_sample'],
      )!,
    );
  }

  @override
  $BooksTable createAlias(String alias) {
    return $BooksTable(attachedDatabase, alias);
  }
}

class BookRow extends DataClass implements Insertable<BookRow> {
  final String id;
  final String title;
  final String? author;
  final String filePath;
  final String? coverPath;
  final int addedAtMs;
  final String? lastLocatorJson;
  final bool isBundledSample;
  const BookRow({
    required this.id,
    required this.title,
    this.author,
    required this.filePath,
    this.coverPath,
    required this.addedAtMs,
    this.lastLocatorJson,
    required this.isBundledSample,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || author != null) {
      map['author'] = Variable<String>(author);
    }
    map['file_path'] = Variable<String>(filePath);
    if (!nullToAbsent || coverPath != null) {
      map['cover_path'] = Variable<String>(coverPath);
    }
    map['added_at_ms'] = Variable<int>(addedAtMs);
    if (!nullToAbsent || lastLocatorJson != null) {
      map['last_locator_json'] = Variable<String>(lastLocatorJson);
    }
    map['is_bundled_sample'] = Variable<bool>(isBundledSample);
    return map;
  }

  BooksCompanion toCompanion(bool nullToAbsent) {
    return BooksCompanion(
      id: Value(id),
      title: Value(title),
      author: author == null && nullToAbsent
          ? const Value.absent()
          : Value(author),
      filePath: Value(filePath),
      coverPath: coverPath == null && nullToAbsent
          ? const Value.absent()
          : Value(coverPath),
      addedAtMs: Value(addedAtMs),
      lastLocatorJson: lastLocatorJson == null && nullToAbsent
          ? const Value.absent()
          : Value(lastLocatorJson),
      isBundledSample: Value(isBundledSample),
    );
  }

  factory BookRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BookRow(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      author: serializer.fromJson<String?>(json['author']),
      filePath: serializer.fromJson<String>(json['filePath']),
      coverPath: serializer.fromJson<String?>(json['coverPath']),
      addedAtMs: serializer.fromJson<int>(json['addedAtMs']),
      lastLocatorJson: serializer.fromJson<String?>(json['lastLocatorJson']),
      isBundledSample: serializer.fromJson<bool>(json['isBundledSample']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'author': serializer.toJson<String?>(author),
      'filePath': serializer.toJson<String>(filePath),
      'coverPath': serializer.toJson<String?>(coverPath),
      'addedAtMs': serializer.toJson<int>(addedAtMs),
      'lastLocatorJson': serializer.toJson<String?>(lastLocatorJson),
      'isBundledSample': serializer.toJson<bool>(isBundledSample),
    };
  }

  BookRow copyWith({
    String? id,
    String? title,
    Value<String?> author = const Value.absent(),
    String? filePath,
    Value<String?> coverPath = const Value.absent(),
    int? addedAtMs,
    Value<String?> lastLocatorJson = const Value.absent(),
    bool? isBundledSample,
  }) => BookRow(
    id: id ?? this.id,
    title: title ?? this.title,
    author: author.present ? author.value : this.author,
    filePath: filePath ?? this.filePath,
    coverPath: coverPath.present ? coverPath.value : this.coverPath,
    addedAtMs: addedAtMs ?? this.addedAtMs,
    lastLocatorJson: lastLocatorJson.present
        ? lastLocatorJson.value
        : this.lastLocatorJson,
    isBundledSample: isBundledSample ?? this.isBundledSample,
  );
  BookRow copyWithCompanion(BooksCompanion data) {
    return BookRow(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      author: data.author.present ? data.author.value : this.author,
      filePath: data.filePath.present ? data.filePath.value : this.filePath,
      coverPath: data.coverPath.present ? data.coverPath.value : this.coverPath,
      addedAtMs: data.addedAtMs.present ? data.addedAtMs.value : this.addedAtMs,
      lastLocatorJson: data.lastLocatorJson.present
          ? data.lastLocatorJson.value
          : this.lastLocatorJson,
      isBundledSample: data.isBundledSample.present
          ? data.isBundledSample.value
          : this.isBundledSample,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BookRow(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('author: $author, ')
          ..write('filePath: $filePath, ')
          ..write('coverPath: $coverPath, ')
          ..write('addedAtMs: $addedAtMs, ')
          ..write('lastLocatorJson: $lastLocatorJson, ')
          ..write('isBundledSample: $isBundledSample')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    author,
    filePath,
    coverPath,
    addedAtMs,
    lastLocatorJson,
    isBundledSample,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BookRow &&
          other.id == this.id &&
          other.title == this.title &&
          other.author == this.author &&
          other.filePath == this.filePath &&
          other.coverPath == this.coverPath &&
          other.addedAtMs == this.addedAtMs &&
          other.lastLocatorJson == this.lastLocatorJson &&
          other.isBundledSample == this.isBundledSample);
}

class BooksCompanion extends UpdateCompanion<BookRow> {
  final Value<String> id;
  final Value<String> title;
  final Value<String?> author;
  final Value<String> filePath;
  final Value<String?> coverPath;
  final Value<int> addedAtMs;
  final Value<String?> lastLocatorJson;
  final Value<bool> isBundledSample;
  final Value<int> rowid;
  const BooksCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.author = const Value.absent(),
    this.filePath = const Value.absent(),
    this.coverPath = const Value.absent(),
    this.addedAtMs = const Value.absent(),
    this.lastLocatorJson = const Value.absent(),
    this.isBundledSample = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BooksCompanion.insert({
    required String id,
    required String title,
    this.author = const Value.absent(),
    required String filePath,
    this.coverPath = const Value.absent(),
    this.addedAtMs = const Value.absent(),
    this.lastLocatorJson = const Value.absent(),
    this.isBundledSample = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title),
       filePath = Value(filePath);
  static Insertable<BookRow> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? author,
    Expression<String>? filePath,
    Expression<String>? coverPath,
    Expression<int>? addedAtMs,
    Expression<String>? lastLocatorJson,
    Expression<bool>? isBundledSample,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (author != null) 'author': author,
      if (filePath != null) 'file_path': filePath,
      if (coverPath != null) 'cover_path': coverPath,
      if (addedAtMs != null) 'added_at_ms': addedAtMs,
      if (lastLocatorJson != null) 'last_locator_json': lastLocatorJson,
      if (isBundledSample != null) 'is_bundled_sample': isBundledSample,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BooksCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String?>? author,
    Value<String>? filePath,
    Value<String?>? coverPath,
    Value<int>? addedAtMs,
    Value<String?>? lastLocatorJson,
    Value<bool>? isBundledSample,
    Value<int>? rowid,
  }) {
    return BooksCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      author: author ?? this.author,
      filePath: filePath ?? this.filePath,
      coverPath: coverPath ?? this.coverPath,
      addedAtMs: addedAtMs ?? this.addedAtMs,
      lastLocatorJson: lastLocatorJson ?? this.lastLocatorJson,
      isBundledSample: isBundledSample ?? this.isBundledSample,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (author.present) {
      map['author'] = Variable<String>(author.value);
    }
    if (filePath.present) {
      map['file_path'] = Variable<String>(filePath.value);
    }
    if (coverPath.present) {
      map['cover_path'] = Variable<String>(coverPath.value);
    }
    if (addedAtMs.present) {
      map['added_at_ms'] = Variable<int>(addedAtMs.value);
    }
    if (lastLocatorJson.present) {
      map['last_locator_json'] = Variable<String>(lastLocatorJson.value);
    }
    if (isBundledSample.present) {
      map['is_bundled_sample'] = Variable<bool>(isBundledSample.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BooksCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('author: $author, ')
          ..write('filePath: $filePath, ')
          ..write('coverPath: $coverPath, ')
          ..write('addedAtMs: $addedAtMs, ')
          ..write('lastLocatorJson: $lastLocatorJson, ')
          ..write('isBundledSample: $isBundledSample, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SentenceTimingsTable extends SentenceTimings
    with TableInfo<$SentenceTimingsTable, SentenceTimingRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SentenceTimingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _chapterHrefMeta = const VerificationMeta(
    'chapterHref',
  );
  @override
  late final GeneratedColumn<String> chapterHref = GeneratedColumn<String>(
    'chapter_href',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _voiceIdMeta = const VerificationMeta(
    'voiceId',
  );
  @override
  late final GeneratedColumn<String> voiceId = GeneratedColumn<String>(
    'voice_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sentenceIndexMeta = const VerificationMeta(
    'sentenceIndex',
  );
  @override
  late final GeneratedColumn<int> sentenceIndex = GeneratedColumn<int>(
    'sentence_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startMsMeta = const VerificationMeta(
    'startMs',
  );
  @override
  late final GeneratedColumn<int> startMs = GeneratedColumn<int>(
    'start_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    bookId,
    chapterHref,
    voiceId,
    sentenceIndex,
    startMs,
    durationMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sentence_timings';
  @override
  VerificationContext validateIntegrity(
    Insertable<SentenceTimingRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('chapter_href')) {
      context.handle(
        _chapterHrefMeta,
        chapterHref.isAcceptableOrUnknown(
          data['chapter_href']!,
          _chapterHrefMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_chapterHrefMeta);
    }
    if (data.containsKey('voice_id')) {
      context.handle(
        _voiceIdMeta,
        voiceId.isAcceptableOrUnknown(data['voice_id']!, _voiceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_voiceIdMeta);
    }
    if (data.containsKey('sentence_index')) {
      context.handle(
        _sentenceIndexMeta,
        sentenceIndex.isAcceptableOrUnknown(
          data['sentence_index']!,
          _sentenceIndexMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sentenceIndexMeta);
    }
    if (data.containsKey('start_ms')) {
      context.handle(
        _startMsMeta,
        startMs.isAcceptableOrUnknown(data['start_ms']!, _startMsMeta),
      );
    } else if (isInserting) {
      context.missing(_startMsMeta);
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    } else if (isInserting) {
      context.missing(_durationMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {
    bookId,
    chapterHref,
    voiceId,
    sentenceIndex,
  };
  @override
  SentenceTimingRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SentenceTimingRow(
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_id'],
      )!,
      chapterHref: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chapter_href'],
      )!,
      voiceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}voice_id'],
      )!,
      sentenceIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sentence_index'],
      )!,
      startMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start_ms'],
      )!,
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      )!,
    );
  }

  @override
  $SentenceTimingsTable createAlias(String alias) {
    return $SentenceTimingsTable(attachedDatabase, alias);
  }
}

class SentenceTimingRow extends DataClass
    implements Insertable<SentenceTimingRow> {
  final String bookId;
  final String chapterHref;
  final String voiceId;
  final int sentenceIndex;
  final int startMs;
  final int durationMs;
  const SentenceTimingRow({
    required this.bookId,
    required this.chapterHref,
    required this.voiceId,
    required this.sentenceIndex,
    required this.startMs,
    required this.durationMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['book_id'] = Variable<String>(bookId);
    map['chapter_href'] = Variable<String>(chapterHref);
    map['voice_id'] = Variable<String>(voiceId);
    map['sentence_index'] = Variable<int>(sentenceIndex);
    map['start_ms'] = Variable<int>(startMs);
    map['duration_ms'] = Variable<int>(durationMs);
    return map;
  }

  SentenceTimingsCompanion toCompanion(bool nullToAbsent) {
    return SentenceTimingsCompanion(
      bookId: Value(bookId),
      chapterHref: Value(chapterHref),
      voiceId: Value(voiceId),
      sentenceIndex: Value(sentenceIndex),
      startMs: Value(startMs),
      durationMs: Value(durationMs),
    );
  }

  factory SentenceTimingRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SentenceTimingRow(
      bookId: serializer.fromJson<String>(json['bookId']),
      chapterHref: serializer.fromJson<String>(json['chapterHref']),
      voiceId: serializer.fromJson<String>(json['voiceId']),
      sentenceIndex: serializer.fromJson<int>(json['sentenceIndex']),
      startMs: serializer.fromJson<int>(json['startMs']),
      durationMs: serializer.fromJson<int>(json['durationMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'bookId': serializer.toJson<String>(bookId),
      'chapterHref': serializer.toJson<String>(chapterHref),
      'voiceId': serializer.toJson<String>(voiceId),
      'sentenceIndex': serializer.toJson<int>(sentenceIndex),
      'startMs': serializer.toJson<int>(startMs),
      'durationMs': serializer.toJson<int>(durationMs),
    };
  }

  SentenceTimingRow copyWith({
    String? bookId,
    String? chapterHref,
    String? voiceId,
    int? sentenceIndex,
    int? startMs,
    int? durationMs,
  }) => SentenceTimingRow(
    bookId: bookId ?? this.bookId,
    chapterHref: chapterHref ?? this.chapterHref,
    voiceId: voiceId ?? this.voiceId,
    sentenceIndex: sentenceIndex ?? this.sentenceIndex,
    startMs: startMs ?? this.startMs,
    durationMs: durationMs ?? this.durationMs,
  );
  SentenceTimingRow copyWithCompanion(SentenceTimingsCompanion data) {
    return SentenceTimingRow(
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      chapterHref: data.chapterHref.present
          ? data.chapterHref.value
          : this.chapterHref,
      voiceId: data.voiceId.present ? data.voiceId.value : this.voiceId,
      sentenceIndex: data.sentenceIndex.present
          ? data.sentenceIndex.value
          : this.sentenceIndex,
      startMs: data.startMs.present ? data.startMs.value : this.startMs,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SentenceTimingRow(')
          ..write('bookId: $bookId, ')
          ..write('chapterHref: $chapterHref, ')
          ..write('voiceId: $voiceId, ')
          ..write('sentenceIndex: $sentenceIndex, ')
          ..write('startMs: $startMs, ')
          ..write('durationMs: $durationMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    bookId,
    chapterHref,
    voiceId,
    sentenceIndex,
    startMs,
    durationMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SentenceTimingRow &&
          other.bookId == this.bookId &&
          other.chapterHref == this.chapterHref &&
          other.voiceId == this.voiceId &&
          other.sentenceIndex == this.sentenceIndex &&
          other.startMs == this.startMs &&
          other.durationMs == this.durationMs);
}

class SentenceTimingsCompanion extends UpdateCompanion<SentenceTimingRow> {
  final Value<String> bookId;
  final Value<String> chapterHref;
  final Value<String> voiceId;
  final Value<int> sentenceIndex;
  final Value<int> startMs;
  final Value<int> durationMs;
  final Value<int> rowid;
  const SentenceTimingsCompanion({
    this.bookId = const Value.absent(),
    this.chapterHref = const Value.absent(),
    this.voiceId = const Value.absent(),
    this.sentenceIndex = const Value.absent(),
    this.startMs = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SentenceTimingsCompanion.insert({
    required String bookId,
    required String chapterHref,
    required String voiceId,
    required int sentenceIndex,
    required int startMs,
    required int durationMs,
    this.rowid = const Value.absent(),
  }) : bookId = Value(bookId),
       chapterHref = Value(chapterHref),
       voiceId = Value(voiceId),
       sentenceIndex = Value(sentenceIndex),
       startMs = Value(startMs),
       durationMs = Value(durationMs);
  static Insertable<SentenceTimingRow> custom({
    Expression<String>? bookId,
    Expression<String>? chapterHref,
    Expression<String>? voiceId,
    Expression<int>? sentenceIndex,
    Expression<int>? startMs,
    Expression<int>? durationMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (bookId != null) 'book_id': bookId,
      if (chapterHref != null) 'chapter_href': chapterHref,
      if (voiceId != null) 'voice_id': voiceId,
      if (sentenceIndex != null) 'sentence_index': sentenceIndex,
      if (startMs != null) 'start_ms': startMs,
      if (durationMs != null) 'duration_ms': durationMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SentenceTimingsCompanion copyWith({
    Value<String>? bookId,
    Value<String>? chapterHref,
    Value<String>? voiceId,
    Value<int>? sentenceIndex,
    Value<int>? startMs,
    Value<int>? durationMs,
    Value<int>? rowid,
  }) {
    return SentenceTimingsCompanion(
      bookId: bookId ?? this.bookId,
      chapterHref: chapterHref ?? this.chapterHref,
      voiceId: voiceId ?? this.voiceId,
      sentenceIndex: sentenceIndex ?? this.sentenceIndex,
      startMs: startMs ?? this.startMs,
      durationMs: durationMs ?? this.durationMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (chapterHref.present) {
      map['chapter_href'] = Variable<String>(chapterHref.value);
    }
    if (voiceId.present) {
      map['voice_id'] = Variable<String>(voiceId.value);
    }
    if (sentenceIndex.present) {
      map['sentence_index'] = Variable<int>(sentenceIndex.value);
    }
    if (startMs.present) {
      map['start_ms'] = Variable<int>(startMs.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SentenceTimingsCompanion(')
          ..write('bookId: $bookId, ')
          ..write('chapterHref: $chapterHref, ')
          ..write('voiceId: $voiceId, ')
          ..write('sentenceIndex: $sentenceIndex, ')
          ..write('startMs: $startMs, ')
          ..write('durationMs: $durationMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$LibraryDatabase extends GeneratedDatabase {
  _$LibraryDatabase(QueryExecutor e) : super(e);
  $LibraryDatabaseManager get managers => $LibraryDatabaseManager(this);
  late final $BooksTable books = $BooksTable(this);
  late final $SentenceTimingsTable sentenceTimings = $SentenceTimingsTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [books, sentenceTimings];
}

typedef $$BooksTableCreateCompanionBuilder =
    BooksCompanion Function({
      required String id,
      required String title,
      Value<String?> author,
      required String filePath,
      Value<String?> coverPath,
      Value<int> addedAtMs,
      Value<String?> lastLocatorJson,
      Value<bool> isBundledSample,
      Value<int> rowid,
    });
typedef $$BooksTableUpdateCompanionBuilder =
    BooksCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<String?> author,
      Value<String> filePath,
      Value<String?> coverPath,
      Value<int> addedAtMs,
      Value<String?> lastLocatorJson,
      Value<bool> isBundledSample,
      Value<int> rowid,
    });

class $$BooksTableFilterComposer
    extends Composer<_$LibraryDatabase, $BooksTable> {
  $$BooksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get author => $composableBuilder(
    column: $table.author,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverPath => $composableBuilder(
    column: $table.coverPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get addedAtMs => $composableBuilder(
    column: $table.addedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastLocatorJson => $composableBuilder(
    column: $table.lastLocatorJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isBundledSample => $composableBuilder(
    column: $table.isBundledSample,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BooksTableOrderingComposer
    extends Composer<_$LibraryDatabase, $BooksTable> {
  $$BooksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get author => $composableBuilder(
    column: $table.author,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverPath => $composableBuilder(
    column: $table.coverPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get addedAtMs => $composableBuilder(
    column: $table.addedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastLocatorJson => $composableBuilder(
    column: $table.lastLocatorJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isBundledSample => $composableBuilder(
    column: $table.isBundledSample,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BooksTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $BooksTable> {
  $$BooksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get author =>
      $composableBuilder(column: $table.author, builder: (column) => column);

  GeneratedColumn<String> get filePath =>
      $composableBuilder(column: $table.filePath, builder: (column) => column);

  GeneratedColumn<String> get coverPath =>
      $composableBuilder(column: $table.coverPath, builder: (column) => column);

  GeneratedColumn<int> get addedAtMs =>
      $composableBuilder(column: $table.addedAtMs, builder: (column) => column);

  GeneratedColumn<String> get lastLocatorJson => $composableBuilder(
    column: $table.lastLocatorJson,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isBundledSample => $composableBuilder(
    column: $table.isBundledSample,
    builder: (column) => column,
  );
}

class $$BooksTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $BooksTable,
          BookRow,
          $$BooksTableFilterComposer,
          $$BooksTableOrderingComposer,
          $$BooksTableAnnotationComposer,
          $$BooksTableCreateCompanionBuilder,
          $$BooksTableUpdateCompanionBuilder,
          (BookRow, BaseReferences<_$LibraryDatabase, $BooksTable, BookRow>),
          BookRow,
          PrefetchHooks Function()
        > {
  $$BooksTableTableManager(_$LibraryDatabase db, $BooksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BooksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BooksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BooksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> author = const Value.absent(),
                Value<String> filePath = const Value.absent(),
                Value<String?> coverPath = const Value.absent(),
                Value<int> addedAtMs = const Value.absent(),
                Value<String?> lastLocatorJson = const Value.absent(),
                Value<bool> isBundledSample = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BooksCompanion(
                id: id,
                title: title,
                author: author,
                filePath: filePath,
                coverPath: coverPath,
                addedAtMs: addedAtMs,
                lastLocatorJson: lastLocatorJson,
                isBundledSample: isBundledSample,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String title,
                Value<String?> author = const Value.absent(),
                required String filePath,
                Value<String?> coverPath = const Value.absent(),
                Value<int> addedAtMs = const Value.absent(),
                Value<String?> lastLocatorJson = const Value.absent(),
                Value<bool> isBundledSample = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BooksCompanion.insert(
                id: id,
                title: title,
                author: author,
                filePath: filePath,
                coverPath: coverPath,
                addedAtMs: addedAtMs,
                lastLocatorJson: lastLocatorJson,
                isBundledSample: isBundledSample,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BooksTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $BooksTable,
      BookRow,
      $$BooksTableFilterComposer,
      $$BooksTableOrderingComposer,
      $$BooksTableAnnotationComposer,
      $$BooksTableCreateCompanionBuilder,
      $$BooksTableUpdateCompanionBuilder,
      (BookRow, BaseReferences<_$LibraryDatabase, $BooksTable, BookRow>),
      BookRow,
      PrefetchHooks Function()
    >;
typedef $$SentenceTimingsTableCreateCompanionBuilder =
    SentenceTimingsCompanion Function({
      required String bookId,
      required String chapterHref,
      required String voiceId,
      required int sentenceIndex,
      required int startMs,
      required int durationMs,
      Value<int> rowid,
    });
typedef $$SentenceTimingsTableUpdateCompanionBuilder =
    SentenceTimingsCompanion Function({
      Value<String> bookId,
      Value<String> chapterHref,
      Value<String> voiceId,
      Value<int> sentenceIndex,
      Value<int> startMs,
      Value<int> durationMs,
      Value<int> rowid,
    });

class $$SentenceTimingsTableFilterComposer
    extends Composer<_$LibraryDatabase, $SentenceTimingsTable> {
  $$SentenceTimingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get chapterHref => $composableBuilder(
    column: $table.chapterHref,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get voiceId => $composableBuilder(
    column: $table.voiceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sentenceIndex => $composableBuilder(
    column: $table.sentenceIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startMs => $composableBuilder(
    column: $table.startMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SentenceTimingsTableOrderingComposer
    extends Composer<_$LibraryDatabase, $SentenceTimingsTable> {
  $$SentenceTimingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chapterHref => $composableBuilder(
    column: $table.chapterHref,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get voiceId => $composableBuilder(
    column: $table.voiceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sentenceIndex => $composableBuilder(
    column: $table.sentenceIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startMs => $composableBuilder(
    column: $table.startMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SentenceTimingsTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $SentenceTimingsTable> {
  $$SentenceTimingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get bookId =>
      $composableBuilder(column: $table.bookId, builder: (column) => column);

  GeneratedColumn<String> get chapterHref => $composableBuilder(
    column: $table.chapterHref,
    builder: (column) => column,
  );

  GeneratedColumn<String> get voiceId =>
      $composableBuilder(column: $table.voiceId, builder: (column) => column);

  GeneratedColumn<int> get sentenceIndex => $composableBuilder(
    column: $table.sentenceIndex,
    builder: (column) => column,
  );

  GeneratedColumn<int> get startMs =>
      $composableBuilder(column: $table.startMs, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );
}

class $$SentenceTimingsTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $SentenceTimingsTable,
          SentenceTimingRow,
          $$SentenceTimingsTableFilterComposer,
          $$SentenceTimingsTableOrderingComposer,
          $$SentenceTimingsTableAnnotationComposer,
          $$SentenceTimingsTableCreateCompanionBuilder,
          $$SentenceTimingsTableUpdateCompanionBuilder,
          (
            SentenceTimingRow,
            BaseReferences<
              _$LibraryDatabase,
              $SentenceTimingsTable,
              SentenceTimingRow
            >,
          ),
          SentenceTimingRow,
          PrefetchHooks Function()
        > {
  $$SentenceTimingsTableTableManager(
    _$LibraryDatabase db,
    $SentenceTimingsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SentenceTimingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SentenceTimingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SentenceTimingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> bookId = const Value.absent(),
                Value<String> chapterHref = const Value.absent(),
                Value<String> voiceId = const Value.absent(),
                Value<int> sentenceIndex = const Value.absent(),
                Value<int> startMs = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SentenceTimingsCompanion(
                bookId: bookId,
                chapterHref: chapterHref,
                voiceId: voiceId,
                sentenceIndex: sentenceIndex,
                startMs: startMs,
                durationMs: durationMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String bookId,
                required String chapterHref,
                required String voiceId,
                required int sentenceIndex,
                required int startMs,
                required int durationMs,
                Value<int> rowid = const Value.absent(),
              }) => SentenceTimingsCompanion.insert(
                bookId: bookId,
                chapterHref: chapterHref,
                voiceId: voiceId,
                sentenceIndex: sentenceIndex,
                startMs: startMs,
                durationMs: durationMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SentenceTimingsTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $SentenceTimingsTable,
      SentenceTimingRow,
      $$SentenceTimingsTableFilterComposer,
      $$SentenceTimingsTableOrderingComposer,
      $$SentenceTimingsTableAnnotationComposer,
      $$SentenceTimingsTableCreateCompanionBuilder,
      $$SentenceTimingsTableUpdateCompanionBuilder,
      (
        SentenceTimingRow,
        BaseReferences<
          _$LibraryDatabase,
          $SentenceTimingsTable,
          SentenceTimingRow
        >,
      ),
      SentenceTimingRow,
      PrefetchHooks Function()
    >;

class $LibraryDatabaseManager {
  final _$LibraryDatabase _db;
  $LibraryDatabaseManager(this._db);
  $$BooksTableTableManager get books =>
      $$BooksTableTableManager(_db, _db.books);
  $$SentenceTimingsTableTableManager get sentenceTimings =>
      $$SentenceTimingsTableTableManager(_db, _db.sentenceTimings);
}
