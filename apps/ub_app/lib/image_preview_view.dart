import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'connection.dart';
import 'image_preview.dart';

class ImagePreviewView extends StatefulWidget {
  const ImagePreviewView({
    super.key,
    required this.session,
    required this.universe,
    required this.context,
    required this.reference,
    this.caption = '',
  });
  final AppSession session;
  final LibraryEntry universe;
  final OpenedContext context;
  final RecordRef reference;
  final String caption;
  @override
  State<ImagePreviewView> createState() => _ImagePreviewViewState();
}

class _ImagePreviewViewState extends State<ImagePreviewView> {
  Uint8List? _bytes;
  ImageAssetRecord? _asset;
  bool _busy = false;
  String? _error;
  int _generation = 0;
  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
      _bytes = null;
      _asset = null;
    });
    try {
      final result = await readImagePreview(
        session: widget.session,
        universe: widget.universe,
        context: widget.context,
        reference: widget.reference,
      );
      if (mounted && generation == _generation) {
        setState(() {
          _bytes = result.bytes;
          _asset = result.asset;
        });
      }
    } on Object {
      if (mounted && generation == _generation) {
        setState(
          () => _error = 'Could not load this preview. Check your connection and access, then retry.',
        );
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  @override
  void didUpdateWidget(covariant ImagePreviewView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reference != widget.reference ||
        oldWidget.context.contextId != widget.context.contextId ||
        oldWidget.universe.id != widget.universe.id ||
        !identical(oldWidget.session, widget.session)) {
      _generation++;
      _bytes = null;
      _asset = null;
      _error = null;
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (widget.caption.isNotEmpty) SelectableText(widget.caption),
      if (_busy) const LinearProgressIndicator(),
      if (_error != null) Semantics(liveRegion: true, child: Text(_error!)),
      if (_bytes != null) ...[
        SizedBox(
          height: 320,
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 6,
            child: Center(
              child: Image.memory(
                _bytes!,
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.contain,
                semanticLabel: widget.caption.isEmpty
                    ? _asset!.originalName
                    : widget.caption,
                errorBuilder: (_, _, _) =>
                    const Text('This preview could not be displayed.'),
              ),
            ),
          ),
        ),
        Text(
          '${_asset!.originalName} · ${_asset!.width} × ${_asset!.height} · ${_asset!.mediaType}',
        ),
        const Text('JPEG preview. Drag or pinch to inspect.'),
      ],
      if (widget.session.author)
        TextButton(
          onPressed: _busy ? null : _load,
          child: Text(
            _bytes == null ? 'Load image preview' : 'Reload image preview',
          ),
        )
      else
        const Text('Image preview is unavailable through this connection.'),
    ],
  );
}
