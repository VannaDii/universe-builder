/// Portable storage values. Native stores have separate library entry points;
/// relational codecs remain internal to their transaction boundaries.
library;

export 'src/saved_settings.dart';
export 'src/revision_input.dart' show Assignment, StoredVersion;
