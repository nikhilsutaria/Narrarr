/// A book in the user's on-device library.
class Book {
  const Book({
    required this.id,
    required this.title,
    required this.filePath,
    this.author,
    this.coverPath,
    this.addedAtMs = 0,
    this.lastLocatorJson,
    this.isBundledSample = false,
  });

  /// Stable id (we use the sandbox filename without extension).
  final String id;
  final String title;
  final String? author;

  /// Absolute path to the EPUB inside the app sandbox (or asset-extracted path
  /// for the bundled sample).
  final String filePath;

  /// Absolute path to an extracted cover image, if any.
  final String? coverPath;

  /// Epoch millis when added (passed in; the app stamps it — `DateTime.now()`
  /// is avoided in pure logic for testability).
  final int addedAtMs;

  /// Serialized flutter_readium `Locator` of the last reading position.
  final String? lastLocatorJson;

  /// True for the seeded sample book bundled with the app.
  final bool isBundledSample;

  Book copyWith({String? lastLocatorJson, String? coverPath}) => Book(
        id: id,
        title: title,
        author: author,
        filePath: filePath,
        coverPath: coverPath ?? this.coverPath,
        addedAtMs: addedAtMs,
        lastLocatorJson: lastLocatorJson ?? this.lastLocatorJson,
        isBundledSample: isBundledSample,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'author': author,
        'filePath': filePath,
        'coverPath': coverPath,
        'addedAtMs': addedAtMs,
        'lastLocatorJson': lastLocatorJson,
        'isBundledSample': isBundledSample,
      };

  factory Book.fromJson(Map<String, dynamic> j) => Book(
        id: j['id'] as String,
        title: j['title'] as String,
        author: j['author'] as String?,
        filePath: j['filePath'] as String,
        coverPath: j['coverPath'] as String?,
        addedAtMs: (j['addedAtMs'] as num?)?.toInt() ?? 0,
        lastLocatorJson: j['lastLocatorJson'] as String?,
        isBundledSample: j['isBundledSample'] as bool? ?? false,
      );
}
