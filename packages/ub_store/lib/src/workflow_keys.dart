/// Shared closed workflow key families; software metadata, never author data.
const workflowFamiliesByPrefix = {
  'context': 'StoredContext',
  'proposal': 'StoredProposal',
  'reserved-record': 'ReservedRecord',
  'validation': 'Checked',
  'operation': 'StoredOperation',
  'request': 'StoredOperation',
  'job': 'StoredOperation',
  'cancel': 'Cancellation',
  'approval': 'ApprovalEvidence',
  'assessment': 'AssessmentEnvelope',
  'assessment-selection': 'AssessmentSelection',
  'assessment-receipt': 'AssessmentReceipt',
  'cursor': 'Cursor',
  'draft': 'SavedDraft',
  'logical-import-origin': 'ImportOrigin',
  'logical-import-admission': 'ImportAdmission',
};

String workflowFamily(String key) =>
    workflowFamiliesByPrefix[key.split(':').first] ??
    (throw const FormatException('Unknown workflow key family'));

(String, int) workflowChunkKey(String key) {
  final suffix = key.substring('image-bytes:'.length);
  final colon = suffix.lastIndexOf(':');
  if (colon < 0) throw const FormatException('Invalid media key');
  final digits = suffix.substring(colon + 1);
  final ordinal = int.tryParse(digits);
  if (ordinal == null || ordinal < 0 || ordinal.toString() != digits) {
    throw const FormatException('Invalid media ordinal');
  }
  return (suffix.substring(0, colon), ordinal);
}
