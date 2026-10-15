import 'package:flutter/material.dart';
import 'package:ub_domain/ub_domain.dart';

import 'record_field_labels.dart';

/// Read-only field layout retains all nested values without a raw JSON editor.
class ExactFields extends StatelessWidget {
  const ExactFields({required this.value, this.authoredKeys = false});
  final CanonicalValue value;
  final bool authoredKeys;
  @override
  Widget build(BuildContext context) => switch (value) {
    CanonicalObject(:final fields) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (fields.isEmpty) const Text('None'),
        for (final field in fields)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  exactFieldLabel(field.key, authoredKeys: authoredKeys),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: ExactFields(
                    value: field.value,
                    authoredKeys: exactChildKeysAreAuthored(
                      field.key,
                      authoredKeys: authoredKeys,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
    CanonicalArray(:final items) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (items.isEmpty) const Text('None'),
        for (var index = 0; index < items.length; index++)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${index + 1}. '),
                Expanded(child: ExactFields(value: items[index])),
              ],
            ),
          ),
      ],
    ),
    CanonicalString(:final value) => SelectableText(
      value.isEmpty ? '(empty)' : value,
    ),
    CanonicalNumber(:final digits) => SelectableText(digits),
    CanonicalBool(:final value) => Text(value ? 'Yes' : 'No'),
    CanonicalNull() => const Text('Not set'),
  };
}
