/// Schema labels must never reinterpret authored dictionary keys.
String exactFieldLabel(String key, {bool authoredKeys = false}) {
  if (authoredKeys) return key;
  return switch (key) {
    'selector' => 'World name',
    'settingType' => 'Setting type',
    'labels' => 'Display labels',
    'aliases' => 'Other names',
    'metadata' => 'Additional details',
    'fictionalDeparture' => 'Fictional departure',
    'classificationResolution' => 'Classification status',
    'worldAssociations' => 'World associations (not location)',
    'record_kind' => 'Record type',
    'kind' => 'Type',
    _ => key.replaceAll('_', ' '),
  };
}

/// Map values retain their normal typed layout. An authored key named "labels"
/// or "fields" is a name, rather than another schema dictionary declaration.
bool exactChildKeysAreAuthored(String key, {bool authoredKeys = false}) =>
    !authoredKeys &&
    const {
      'labels',
      'metadata',
      'qualifiers',
      'fields',
      'unitStructure',
      'dependencies',
    }.contains(key);
