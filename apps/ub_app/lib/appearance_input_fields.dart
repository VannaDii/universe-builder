import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'draft_record_choice_field.dart';
import 'draft_record_choices.dart';
import 'image_preview_view.dart';
import 'connection.dart';
import 'saved_changes.dart';

class AppearanceInputFields extends StatefulWidget {
  const AppearanceInputFields({
    super.key,
    required this.changes,
    required this.draft,
    required this.form,
    required this.disabled,
    required this.onChanged,
    this.onPickImage,
  });
  final SavedChanges changes;
  final SavedDraft draft;
  final UnfinishedAppearanceForm form;
  final bool disabled;
  final ValueChanged<UnfinishedAppearanceForm> onChanged;
  final VoidCallback? onPickImage;
  @override
  State<AppearanceInputFields> createState() => _AppearanceInputFieldsState();
}

class _AppearanceInputFieldsState extends State<AppearanceInputFields> {
  int _layout = 0;
  RecordRef? _publishedReference(ExpressionReferenceInput input) {
    try {
      return RecordRef(
        record: RecordId.parse(input.record),
        universe: input.universe.isEmpty
            ? null
            : UniverseId.parse(input.universe),
      );
    } on FormatException {
      return null;
    }
  }

  Widget _text(
    String label,
    String value,
    ValueChanged<String> change, {
    int lines = 1,
  }) => TextFormField(
    key: ValueKey(label),
    initialValue: value,
    enabled: !widget.disabled,
    maxLines: lines,
    decoration: InputDecoration(labelText: label),
    onChanged: change,
  );
  Widget _choice(
    String label,
    String selected,
    Map<String, String> options,
    ValueChanged<String> change,
  ) => DropdownButtonFormField<String>(
    key: ValueKey((label, selected)),
    initialValue: selected.isEmpty ? null : selected,
    decoration: InputDecoration(labelText: label),
    items: options.entries
        .map(
          (entry) =>
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
        )
        .toList(),
    onChanged: widget.disabled ? null : (value) => change(value!),
  );
  Widget _reference(
    String label,
    ExpressionReferenceInput input,
    ValueChanged<ExpressionReferenceInput> change, {
    RecordKind? kind,
  }) => DraftRecordChoiceField(
    changes: widget.changes,
    draft: widget.draft,
    kind: kind,
    label: label,
    record: input.record,
    universe: input.universe,
    disabled: widget.disabled,
    onChanged: (ref) => change(
      ExpressionReferenceInput(
        record: ref.record.value,
        universe: ref.universe?.value ?? '',
      ),
    ),
  );
  Widget _order(
    int index,
    int length,
    void Function(int) move,
    VoidCallback remove,
  ) => Wrap(
    children: [
      TextButton(
        onPressed: widget.disabled || index == 0
            ? null
            : () {
                _layout++;
                move(index - 1);
              },
        child: const Text('Move up'),
      ),
      TextButton(
        onPressed: widget.disabled || index == length - 1
            ? null
            : () {
                _layout++;
                move(index + 1);
              },
        child: const Text('Move down'),
      ),
      TextButton(
        onPressed: widget.disabled
            ? null
            : () {
                _layout++;
                remove();
              },
        child: const Text('Remove'),
      ),
    ],
  );
  void _image(int index, AppearanceImageInput image) {
    final images = [...widget.form.images];
    images[index] = image;
    widget.onChanged(widget.form.copyWith(images: images));
  }

  void _link(int index, AppearanceLinkInput link) {
    final links = [...widget.form.links];
    links[index] = link;
    widget.onChanged(widget.form.copyWith(links: links));
  }

  @override
  Widget build(BuildContext context) {
    final form = widget.form;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _choice('What does this appearance describe?', form.targetKind, {
          'universe': 'This universe',
          'entry': 'A named entry',
        }, (kind) => widget.onChanged(form.copyWith(targetKind: kind))),
        if (form.targetKind == 'entry')
          _reference(
            'Appearance target',
            form.target,
            (target) => widget.onChanged(form.copyWith(target: target)),
          ),
        _text(
          'Appearance label',
          form.label,
          (value) => widget.onChanged(form.copyWith(label: value)),
        ),
        _text(
          'Physical description',
          form.physicalDescription,
          (value) =>
              widget.onChanged(form.copyWith(physicalDescription: value)),
          lines: 5,
        ),
        _text(
          'Atmosphere',
          form.atmosphere,
          (value) => widget.onChanged(form.copyWith(atmosphere: value)),
          lines: 3,
        ),
        const SizedBox(height: 16),
        const Text('Images'),
        const Text(
          'Choose an imported asset or retain a selected PNG, JPEG or WebP. Retaining an original does not publish it.',
        ),
        for (var i = 0; i < form.images.length; i++)
          Card(
            key: ValueKey((_layout, 'image', i)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Image ${i + 1}'),
                  if (form.images[i].stagedOperation case final op?) ...[
                    Text(
                      '${op.record.originalName} · ${op.record.width} × ${op.record.height} · ${op.record.mediaType}',
                    ),
                    const Text('Original retained; not yet published.'),
                    if (form.images[i].preview.isNotEmpty)
                      SizedBox(
                        height: 220,
                        child: InteractiveViewer(
                          minScale: 1,
                          maxScale: 6,
                          child: Image.memory(
                            decodeImagePreviewBytes(form.images[i].preview),
                            semanticLabel: form.images[i].caption.isEmpty
                                ? 'Retained image preview'
                                : form.images[i].caption,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                  ],
                  if (form.images[i].stagedOperation == null)
                    _reference(
                      'Image asset ${i + 1}',
                      form.images[i].asset,
                      (asset) =>
                          _image(i, form.images[i].copyWith(asset: asset)),
                      kind: RecordKind.imageAsset,
                    ),
                  if (form.images[i].stagedOperation != null)
                    TextButton(
                      onPressed: widget.disabled
                          ? null
                          : () => _image(
                              i,
                              form.images[i].copyWith(
                                asset: const ExpressionReferenceInput(),
                              ),
                            ),
                      child: const Text('Choose existing image instead'),
                    ),
                  if (form.images[i].stagedOperation == null)
                    if (_publishedReference(form.images[i].asset)
                        case final ref?)
                      _PublishedAppearanceImage(
                        changes: widget.changes,
                        draft: widget.draft,
                        reference: ref,
                      ),
                  _text(
                    'Image ${i + 1} caption',
                    form.images[i].caption,
                    (value) =>
                        _image(i, form.images[i].copyWith(caption: value)),
                    lines: 2,
                  ),
                  _choice(
                    'Image ${i + 1} purpose',
                    form.images[i].purpose,
                    {
                      'appearance': 'Appearance',
                      'detail': 'Detail',
                      'inspiration': 'Inspiration',
                    },
                    (purpose) =>
                        _image(i, form.images[i].copyWith(purpose: purpose)),
                  ),
                  _order(
                    i,
                    form.images.length,
                    (next) {
                      final images = [...form.images],
                          image = images.removeAt(i);
                      images.insert(next, image);
                      widget.onChanged(form.copyWith(images: images));
                    },
                    () => widget.onChanged(
                      form.copyWith(images: [...form.images]..removeAt(i)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Wrap(
          children: [
            TextButton(
              onPressed: widget.disabled
                  ? null
                  : () => widget.onChanged(
                      form.copyWith(
                        images: [...form.images, const AppearanceImageInput()],
                      ),
                    ),
              child: const Text('Add existing image'),
            ),
            if (widget.onPickImage != null)
              TextButton(
                onPressed: widget.disabled ? null : widget.onPickImage,
                child: const Text('Choose image file'),
              ),
          ],
        ),
        const SizedBox(height: 16),
        const Text('Depiction links'),
        for (var i = 0; i < form.links.length; i++)
          Card(
            key: ValueKey((_layout, 'link', i)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _reference(
                    'Linked entry ${i + 1}',
                    form.links[i].entry,
                    (entry) => _link(i, form.links[i].copyWith(entry: entry)),
                  ),
                  _choice(
                    'Link ${i + 1} relationship',
                    form.links[i].relationship,
                    {
                      'matches': 'Matches',
                      'complements': 'Complements',
                      'contrasts': 'Contrasts',
                      'detail_of': 'Detail of',
                    },
                    (relationship) => _link(
                      i,
                      form.links[i].copyWith(relationship: relationship),
                    ),
                  ),
                  _text(
                    'Link ${i + 1} note',
                    form.links[i].note,
                    (value) => _link(i, form.links[i].copyWith(note: value)),
                    lines: 2,
                  ),
                  _order(
                    i,
                    form.links.length,
                    (next) {
                      final links = [...form.links], link = links.removeAt(i);
                      links.insert(next, link);
                      widget.onChanged(form.copyWith(links: links));
                    },
                    () => widget.onChanged(
                      form.copyWith(links: [...form.links]..removeAt(i)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        TextButton(
          onPressed: widget.disabled
              ? null
              : () => widget.onChanged(
                  form.copyWith(
                    links: [...form.links, const AppearanceLinkInput()],
                  ),
                ),
          child: const Text('Add depiction link'),
        ),
        _choice('When does this appearance apply?', form.validityKind, {
          'unspecified': 'Time scope unspecified',
          'calendar_interval': 'Authored calendar interval',
          if (form.original != null)
            'retain': 'Keep current authored time scope',
        }, (kind) => widget.onChanged(form.copyWith(validityKind: kind))),
        if (form.validityKind == 'calendar_interval') ...[
          const Text(
            'Start is inclusive; end is exclusive. Use the selected calendar’s whole-tick coordinates. This does not change the story clock.',
          ),
          _reference(
            'Calendar',
            ExpressionReferenceInput(
              record: form.calendar.replaceFirst('cal_', 'rec_'),
              universe: widget.changes.scope.universe.value,
            ),
            (calendar) => widget.onChanged(
              form.copyWith(
                calendar: calendar.record.replaceFirst('rec_', 'cal_'),
              ),
            ),
            kind: RecordKind.calendar,
          ),
          SwitchListTile(
            title: const Text('Start explicitly unbounded'),
            value: form.startUnbounded,
            onChanged: widget.disabled
                ? null
                : (value) =>
                      widget.onChanged(form.copyWith(startUnbounded: value)),
          ),
          if (!form.startUnbounded)
            _text(
              'Start coordinate',
              form.start,
              (value) => widget.onChanged(form.copyWith(start: value)),
            ),
          SwitchListTile(
            title: const Text('End explicitly unbounded'),
            value: form.endUnbounded,
            onChanged: widget.disabled
                ? null
                : (value) =>
                      widget.onChanged(form.copyWith(endUnbounded: value)),
          ),
          if (!form.endUnbounded)
            _text(
              'End coordinate',
              form.end,
              (value) => widget.onChanged(form.copyWith(end: value)),
            ),
        ],
      ],
    );
  }
}

class _PublishedAppearanceImage extends StatefulWidget {
  const _PublishedAppearanceImage({
    required this.changes,
    required this.draft,
    required this.reference,
  });
  final SavedChanges changes;
  final SavedDraft draft;
  final RecordRef reference;
  @override
  State<_PublishedAppearanceImage> createState() =>
      _PublishedAppearanceImageState();
}

class _PublishedAppearanceImageState extends State<_PublishedAppearanceImage> {
  late Future<OpenedContext> _context;
  @override
  void initState() {
    super.initState();
    _context = openDraftChoiceContext(widget.changes, widget.draft);
  }

  @override
  void didUpdateWidget(covariant _PublishedAppearanceImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reference != widget.reference ||
        oldWidget.draft.content.baseRevision !=
            widget.draft.content.baseRevision ||
        oldWidget.changes.session != widget.changes.session) {
      _context = openDraftChoiceContext(widget.changes, widget.draft);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<OpenedContext>(
    future: _context,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Text(
          'Published image preview unavailable in this draft context.',
        );
      }
      if (!snapshot.hasData) return const LinearProgressIndicator();
      return ImagePreviewView(
        session: widget.changes.session,
        universe: LibraryEntry(
          widget.changes.scope.universe,
          widget.changes.universe.value,
        ),
        context: snapshot.data!,
        reference: widget.reference,
      );
    },
  );
}
