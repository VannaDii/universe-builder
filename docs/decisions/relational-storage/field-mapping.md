# Exact field mapping

Generated from current domain schemas and checked-in public contracts. Private envelopes are explicitly specified in `build_schema.py`; DraftContent.operations deliberately proposes typed operations instead of legacy raw editor JSON, whose conversion can be blocked (see compatibility.md). `__state`: 0 absent, 1 explicit null, 2 value. Collections use child rows; an empty collection still has a header. Numeric wire tokens use decimal TEXT, never SQLite REAL.

| Contract | Table / scalar domain | Fields or links |
|---|---|---|
| `TypeDefinitionV3` | `r_type_definition_v3` | namespace → TypeDefinitionV3_namespace, key → TypeDefinitionV3_key, labels → TypeDefinitionV3_labels, classificationExecutable → TypeDefinitionV3_classificationExecutable, name → TypeDefinitionV3_name, parent → TypeDefinitionV3_parent, applicability → Applicability |
| `TypeDefinitionV3_namespace` | `r_type_definition_v3_namespace` (scalar column) | string |
| `TypeDefinitionV3_key` | `r_type_definition_v3_key` (scalar column) | string |
| `TypeDefinitionV3_labels` | `r_type_definition_v3_labels` | TypeDefinitionV3_labels_item |
| `TypeDefinitionV3_labels_item` | `r_type_definition_v3_labels_item` (scalar column) | string |
| `TypeDefinitionV3_classificationExecutable` | `r_type_definition_v3_classification_executable` (scalar column) | boolean |
| `TypeDefinitionV3_name` | `r_type_definition_v3_name` (scalar column) | string |
| `TypeDefinitionV3_parent` | `r_type_definition_v3_parent` | RecordId, TypeDefinitionV3_parent_v1 |
| `RecordId` | `r_record_id` (scalar column) | string |
| `TypeDefinitionV3_parent_v1` | `r_type_definition_v3_parent_v1` (scalar column) | null |
| `Applicability` | `r_applicability` | Applicability_v0, Applicability_v1, Applicability_v2, Applicability_v3 |
| `Applicability_v0` | `r_applicability_v0` | kind → Applicability_v0_kind |
| `Applicability_v0_kind` | `r_applicability_v0_kind` (scalar column) | string |
| `Applicability_v1` | `r_applicability_v1` | world_ids → Applicability_v1_world_ids, kind → Applicability_v1_kind |
| `Applicability_v1_world_ids` | `r_applicability_v1_world_ids` | WorldId |
| `WorldId` | `r_world_id` (scalar column) | string |
| `Applicability_v1_kind` | `r_applicability_v1_kind` (scalar column) | string |
| `Applicability_v2` | `r_applicability_v2` | kind → Applicability_v2_kind |
| `Applicability_v2_kind` | `r_applicability_v2_kind` (scalar column) | string |
| `Applicability_v3` | `r_applicability_v3` | kind → Applicability_v3_kind |
| `Applicability_v3_kind` | `r_applicability_v3_kind` (scalar column) | string |
| `InstanceV3` | `r_instance_v3` | names → InstanceV3_names, worldAssociations → InstanceV3_worldAssociations, labels → InstanceV3_labels, metadata → InstanceV3_metadata, classification → InstanceV3_classification |
| `InstanceV3_names` | `r_instance_v3_names` | ContextualName |
| `ContextualName` | `r_contextual_name` | text → ContextualName_text, language → ContextualName_language, community → ContextualName_community, role → ContextualName_role, validity → Validity |
| `ContextualName_text` | `r_contextual_name_text` (scalar column) | string |
| `ContextualName_language` | `r_contextual_name_language` | ContextualName_language_v0, ContextualName_language_v1 |
| `ContextualName_language_v0` | `r_contextual_name_language_v0` (scalar column) | string |
| `ContextualName_language_v1` | `r_contextual_name_language_v1` (scalar column) | null |
| `ContextualName_community` | `r_contextual_name_community` | ContextualName_community_v0, ContextualName_community_v1 |
| `ContextualName_community_v0` | `r_contextual_name_community_v0` (scalar column) | string |
| `ContextualName_community_v1` | `r_contextual_name_community_v1` (scalar column) | null |
| `ContextualName_role` | `r_contextual_name_role` | ContextualName_role_v0, ContextualName_role_v1 |
| `ContextualName_role_v0` | `r_contextual_name_role_v0` (scalar column) | string |
| `ContextualName_role_v1` | `r_contextual_name_role_v1` (scalar column) | null |
| `Validity` | `r_validity` | Validity_v0, Validity_v1, Validity_v2, Validity_v3, Validity_v4, Validity_v5, Validity_v6 |
| `Validity_v0` | `r_validity_v0` | kind → Validity_v0_kind |
| `Validity_v0_kind` | `r_validity_v0_kind` (scalar column) | string |
| `Validity_v1` | `r_validity_v1` | kind → Validity_v1_kind |
| `Validity_v1_kind` | `r_validity_v1_kind` (scalar column) | string |
| `Validity_v2` | `r_validity_v2` | at → TemporalExpression, kind → Validity_v2_kind |
| `TemporalExpression` | `r_temporal_expression` | TemporalExpression_v0, TemporalExpression_v1, TemporalExpression_v2, TemporalExpression_v3, TemporalExpression_v4, TemporalExpression_v5 |
| `TemporalExpression_v0` | `r_temporal_expression_v0` | calendar → CalendarId, value → TemporalExpression_v0_value, kind → TemporalExpression_v0_kind |
| `CalendarId` | `r_calendar_id` (scalar column) | string |
| `TemporalExpression_v0_value` | `r_temporal_expression_v0_value` (scalar column) | string |
| `TemporalExpression_v0_kind` | `r_temporal_expression_v0_kind` (scalar column) | string |
| `TemporalExpression_v1` | `r_temporal_expression_v1` | calendar → CalendarId, start → TemporalBound, end → TemporalBound, kind → TemporalExpression_v1_kind |
| `TemporalBound` | `r_temporal_bound` | TemporalBound_v0, TemporalBound_v1, TemporalBound_v2, TemporalBound_v3, TemporalBound_v4 |
| `TemporalBound_v0` | `r_temporal_bound_v0` | kind → TemporalBound_v0_kind |
| `TemporalBound_v0_kind` | `r_temporal_bound_v0_kind` (scalar column) | string |
| `TemporalBound_v1` | `r_temporal_bound_v1` | kind → TemporalBound_v1_kind |
| `TemporalBound_v1_kind` | `r_temporal_bound_v1_kind` (scalar column) | string |
| `TemporalBound_v2` | `r_temporal_bound_v2` | value → TemporalBound_v2_value, kind → TemporalBound_v2_kind |
| `TemporalBound_v2_value` | `r_temporal_bound_v2_value` (scalar column) | string |
| `TemporalBound_v2_kind` | `r_temporal_bound_v2_kind` (scalar column) | string |
| `TemporalBound_v3` | `r_temporal_bound_v3` | value → TemporalBound_v3_value, uncertainty → Value, kind → TemporalBound_v3_kind |
| `TemporalBound_v3_value` | `r_temporal_bound_v3_value` (scalar column) | string |
| `Value` | `r_value` | Value_v0, Value_v1, Value_v2, Value_v3, Value_v4, Value_v5, Value_v6, Value_v7, Value_v8, Value_v9, Value_v10, Value_v11, Value_v12, Value_v13, Value_v14, Value_v15 |
| `Value_v0` | `r_value_v0` | text → Value_v0_text, kind → Value_v0_kind |
| `Value_v0_text` | `r_value_v0_text` (scalar column) | string |
| `Value_v0_kind` | `r_value_v0_kind` (scalar column) | string |
| `Value_v1` | `r_value_v1` | value → Value_v1_value, kind → Value_v1_kind |
| `Value_v1_value` | `r_value_v1_value` (scalar column) | boolean |
| `Value_v1_kind` | `r_value_v1_kind` (scalar column) | string |
| `Value_v2` | `r_value_v2` | digits → Value_v2_digits, kind → Value_v2_kind |
| `Value_v2_digits` | `r_value_v2_digits` (scalar column) | string |
| `Value_v2_kind` | `r_value_v2_kind` (scalar column) | string |
| `Value_v3` | `r_value_v3` | digits → Value_v3_digits, kind → Value_v3_kind |
| `Value_v3_digits` | `r_value_v3_digits` (scalar column) | string |
| `Value_v3_kind` | `r_value_v3_kind` (scalar column) | string |
| `Value_v4` | `r_value_v4` | numerator → Value_v4_numerator, denominator → Value_v4_denominator, kind → Value_v4_kind |
| `Value_v4_numerator` | `r_value_v4_numerator` (scalar column) | string |
| `Value_v4_denominator` | `r_value_v4_denominator` (scalar column) | string |
| `Value_v4_kind` | `r_value_v4_kind` (scalar column) | string |
| `Value_v5` | `r_value_v5` | value → Value, unit → UnitId, kind → Value_v5_kind |
| `UnitId` | `r_unit_id` (scalar column) | string |
| `Value_v5_kind` | `r_value_v5_kind` (scalar column) | string |
| `Value_v6` | `r_value_v6` | lower → Value, upper → Value, lower_inclusive → Value_v6_lower_inclusive, upper_inclusive → Value_v6_upper_inclusive, unit → Value_v6_unit, kind → Value_v6_kind |
| `Value_v6_lower_inclusive` | `r_value_v6_lower_inclusive` (scalar column) | boolean |
| `Value_v6_upper_inclusive` | `r_value_v6_upper_inclusive` (scalar column) | boolean |
| `Value_v6_unit` | `r_value_v6_unit` | UnitId, Value_v6_unit_v1 |
| `Value_v6_unit_v1` | `r_value_v6_unit_v1` (scalar column) | null |
| `Value_v6_kind` | `r_value_v6_kind` (scalar column) | string |
| `Value_v7` | `r_value_v7` | ref → RecordRef, kind → Value_v7_kind |
| `RecordRef` | `r_record_ref` | universe → RecordRef_universe, record → RecordId |
| `RecordRef_universe` | `r_record_ref_universe` | UniverseId, RecordRef_universe_v1 |
| `UniverseId` | `r_universe_id` (scalar column) | string |
| `RecordRef_universe_v1` | `r_record_ref_universe_v1` (scalar column) | null |
| `Value_v7_kind` | `r_value_v7_kind` (scalar column) | string |
| `Value_v8` | `r_value_v8` | ref → RecordRef, kind → Value_v8_kind |
| `Value_v8_kind` | `r_value_v8_kind` (scalar column) | string |
| `Value_v9` | `r_value_v9` | ref → RecordRef, kind → Value_v9_kind |
| `Value_v9_kind` | `r_value_v9_kind` (scalar column) | string |
| `Value_v10` | `r_value_v10` | temporal → TemporalExpression, kind → Value_v10_kind |
| `Value_v10_kind` | `r_value_v10_kind` (scalar column) | string |
| `Value_v11` | `r_value_v11` | spatial → SpatialExpression, kind → Value_v11_kind |
| `SpatialExpression` | `r_spatial_expression` | SpatialExpression_v0, SpatialExpression_v1, SpatialExpression_v2, SpatialExpression_v3, SpatialExpression_v4, SpatialExpression_v5 |
| `SpatialExpression_v0` | `r_spatial_expression_v0` | target → RecordRef, kind → SpatialExpression_v0_kind |
| `SpatialExpression_v0_kind` | `r_spatial_expression_v0_kind` (scalar column) | string |
| `SpatialExpression_v1` | `r_spatial_expression_v1` | target → RecordRef, kind → SpatialExpression_v1_kind |
| `SpatialExpression_v1_kind` | `r_spatial_expression_v1_kind` (scalar column) | string |
| `SpatialExpression_v2` | `r_spatial_expression_v2` | target → RecordRef, kind → SpatialExpression_v2_kind |
| `SpatialExpression_v2_kind` | `r_spatial_expression_v2_kind` (scalar column) | string |
| `SpatialExpression_v3` | `r_spatial_expression_v3` | reference → SpatialExpression_v3_reference, values → SpatialExpression_v3_values, kind → SpatialExpression_v3_kind |
| `SpatialExpression_v3_reference` | `r_spatial_expression_v3_reference` (scalar column) | string |
| `SpatialExpression_v3_values` | `r_spatial_expression_v3_values` | Value |
| `SpatialExpression_v3_kind` | `r_spatial_expression_v3_kind` (scalar column) | string |
| `SpatialExpression_v4` | `r_spatial_expression_v4` | from → RecordRef, value → Value, unit → UnitId, kind → SpatialExpression_v4_kind |
| `SpatialExpression_v4_kind` | `r_spatial_expression_v4_kind` (scalar column) | string |
| `SpatialExpression_v5` | `r_spatial_expression_v5` | kind → SpatialExpression_v5_kind |
| `SpatialExpression_v5_kind` | `r_spatial_expression_v5_kind` (scalar column) | string |
| `Value_v11_kind` | `r_value_v11_kind` (scalar column) | string |
| `Value_v12` | `r_value_v12` | definition → ValueDefinitionId, key → Value_v12_key, kind → Value_v12_kind |
| `ValueDefinitionId` | `r_value_definition_id` (scalar column) | string |
| `Value_v12_key` | `r_value_v12_key` (scalar column) | string |
| `Value_v12_kind` | `r_value_v12_kind` (scalar column) | string |
| `Value_v13` | `r_value_v13` | items → Value_v13_items, kind → Value_v13_kind |
| `Value_v13_items` | `r_value_v13_items` | Value |
| `Value_v13_kind` | `r_value_v13_kind` (scalar column) | string |
| `Value_v14` | `r_value_v14` | items → Value_v14_items, kind → Value_v14_kind |
| `Value_v14_items` | `r_value_v14_items` | Value |
| `Value_v14_kind` | `r_value_v14_kind` (scalar column) | string |
| `Value_v15` | `r_value_v15` | definition → ValueDefinitionId, fields → Value_v15_fields, kind → Value_v15_kind |
| `Value_v15_fields` | `r_value_v15_fields` | Value |
| `Value_v15_kind` | `r_value_v15_kind` (scalar column) | string |
| `TemporalBound_v3_kind` | `r_temporal_bound_v3_kind` (scalar column) | string |
| `TemporalBound_v4` | `r_temporal_bound_v4` | lower → TemporalBound_v4_lower, upper → TemporalBound_v4_upper, kind → TemporalBound_v4_kind |
| `TemporalBound_v4_lower` | `r_temporal_bound_v4_lower` (scalar column) | string |
| `TemporalBound_v4_upper` | `r_temporal_bound_v4_upper` (scalar column) | string |
| `TemporalBound_v4_kind` | `r_temporal_bound_v4_kind` (scalar column) | string |
| `TemporalExpression_v1_kind` | `r_temporal_expression_v1_kind` (scalar column) | string |
| `TemporalExpression_v2` | `r_temporal_expression_v2` | calendar → CalendarId, value → TemporalExpression_v2_value, uncertainty → Value, kind → TemporalExpression_v2_kind |
| `TemporalExpression_v2_value` | `r_temporal_expression_v2_value` (scalar column) | string |
| `TemporalExpression_v2_kind` | `r_temporal_expression_v2_kind` (scalar column) | string |
| `TemporalExpression_v3` | `r_temporal_expression_v3` | calendar → CalendarId, amount → Value, kind → TemporalExpression_v3_kind |
| `TemporalExpression_v3_kind` | `r_temporal_expression_v3_kind` (scalar column) | string |
| `TemporalExpression_v4` | `r_temporal_expression_v4` | calendar → CalendarId, relation → TemporalRelation, target → RecordRef, kind → TemporalExpression_v4_kind |
| `TemporalRelation` | `r_temporal_relation` | TemporalRelation_v0, TemporalRelation_v1, TemporalRelation_v2, TemporalRelation_v3, TemporalRelation_v4 |
| `TemporalRelation_v0` | `r_temporal_relation_v0` (scalar column) | string |
| `TemporalRelation_v1` | `r_temporal_relation_v1` (scalar column) | string |
| `TemporalRelation_v2` | `r_temporal_relation_v2` (scalar column) | string |
| `TemporalRelation_v3` | `r_temporal_relation_v3` (scalar column) | string |
| `TemporalRelation_v4` | `r_temporal_relation_v4` (scalar column) | string |
| `TemporalExpression_v4_kind` | `r_temporal_expression_v4_kind` (scalar column) | string |
| `TemporalExpression_v5` | `r_temporal_expression_v5` | kind → TemporalExpression_v5_kind |
| `TemporalExpression_v5_kind` | `r_temporal_expression_v5_kind` (scalar column) | string |
| `Validity_v2_kind` | `r_validity_v2_kind` (scalar column) | string |
| `Validity_v3` | `r_validity_v3` | start → TemporalBound, end → TemporalBound, kind → Validity_v3_kind |
| `Validity_v3_kind` | `r_validity_v3_kind` (scalar column) | string |
| `Validity_v4` | `r_validity_v4` | calendar → CalendarId, start → TemporalBound, end → TemporalBound, kind → Validity_v4_kind |
| `Validity_v4_kind` | `r_validity_v4_kind` (scalar column) | string |
| `Validity_v5` | `r_validity_v5` | from → TemporalBound, kind → Validity_v5_kind |
| `Validity_v5_kind` | `r_validity_v5_kind` (scalar column) | string |
| `Validity_v6` | `r_validity_v6` | kind → Validity_v6_kind |
| `Validity_v6_kind` | `r_validity_v6_kind` (scalar column) | string |
| `InstanceV3_worldAssociations` | `r_instance_v3_world_associations` | WorldAssociation |
| `WorldAssociation` | `r_world_association` | world → WorldId, role → WorldAssociation_role, validity → Validity, qualifiers → WorldAssociation_qualifiers |
| `WorldAssociation_role` | `r_world_association_role` (scalar column) | string |
| `WorldAssociation_qualifiers` | `r_world_association_qualifiers` | Value |
| `InstanceV3_labels` | `r_instance_v3_labels` | InstanceV3_labels_item |
| `InstanceV3_labels_item` | `r_instance_v3_labels_item` (scalar column) | string |
| `InstanceV3_metadata` | `r_instance_v3_metadata` | Value |
| `InstanceV3_classification` | `r_instance_v3_classification` | RecordId, InstanceV3_classification_v1 |
| `InstanceV3_classification_v1` | `r_instance_v3_classification_v1` (scalar column) | null |
| `AttributeAssertionV3` | `r_attribute_assertion_v3` | proposition → RecordRef, polarity → Polarity, scope → Scope, validity → Validity, persistence → PersistenceSemantics, precision → Precision, alternatives → AttributeAssertionV3_alternatives, basis → EvidenceBasis, establishedBy → AttributeAssertionV3_establishedBy, attributeMode → AttributeAssertionV3_attributeMode |
| `Polarity` | `r_polarity` (scalar column) | string |
| `Scope` | `r_scope` | applicability → Applicability, context → RecordRef, realm → Scope_realm |
| `Scope_realm` | `r_scope_realm` | RecordRef, Scope_realm_v1 |
| `Scope_realm_v1` | `r_scope_realm_v1` (scalar column) | null |
| `PersistenceSemantics` | `r_persistence_semantics` | PersistenceSemantics_v0, PersistenceSemantics_v1, PersistenceSemantics_v2, PersistenceSemantics_v3, PersistenceSemantics_v4 |
| `PersistenceSemantics_v0` | `r_persistence_semantics_v0` (scalar column) | string |
| `PersistenceSemantics_v1` | `r_persistence_semantics_v1` (scalar column) | string |
| `PersistenceSemantics_v2` | `r_persistence_semantics_v2` (scalar column) | string |
| `PersistenceSemantics_v3` | `r_persistence_semantics_v3` (scalar column) | string |
| `PersistenceSemantics_v4` | `r_persistence_semantics_v4` (scalar column) | string |
| `Precision` | `r_precision` (scalar column) | string |
| `AttributeAssertionV3_alternatives` | `r_attribute_assertion_v3_alternatives` | Value |
| `EvidenceBasis` | `r_evidence_basis` | EvidenceBasis_v0, EvidenceBasis_v1, EvidenceBasis_v2, EvidenceBasis_v3, EvidenceBasis_v4 |
| `EvidenceBasis_v0` | `r_evidence_basis_v0` | note → EvidenceBasis_v0_note, kind → EvidenceBasis_v0_kind |
| `EvidenceBasis_v0_note` | `r_evidence_basis_v0_note` (scalar column) | string |
| `EvidenceBasis_v0_kind` | `r_evidence_basis_v0_kind` (scalar column) | string |
| `EvidenceBasis_v1` | `r_evidence_basis_v1` | anchor → RecordRef, verified → EvidenceBasis_v1_verified, kind → EvidenceBasis_v1_kind |
| `EvidenceBasis_v1_verified` | `r_evidence_basis_v1_verified` (scalar column) | boolean |
| `EvidenceBasis_v1_kind` | `r_evidence_basis_v1_kind` (scalar column) | string |
| `EvidenceBasis_v2` | `r_evidence_basis_v2` | event → RecordRef, slot → EvidenceBasis_v2_slot, kind → EvidenceBasis_v2_kind |
| `EvidenceBasis_v2_slot` | `r_evidence_basis_v2_slot` (scalar column) | string |
| `EvidenceBasis_v2_kind` | `r_evidence_basis_v2_kind` (scalar column) | string |
| `EvidenceBasis_v3` | `r_evidence_basis_v3` | kind → EvidenceBasis_v3_kind |
| `EvidenceBasis_v3_kind` | `r_evidence_basis_v3_kind` (scalar column) | string |
| `EvidenceBasis_v4` | `r_evidence_basis_v4` | chain → EvidenceBasis_v4_chain, evaluator → EvidenceBasis_v4_evaluator, kind → EvidenceBasis_v4_kind |
| `EvidenceBasis_v4_chain` | `r_evidence_basis_v4_chain` | VersionRef |
| `VersionRef` | `r_version_ref` | universe → VersionRef_universe, record → RecordId, version → RecordVersionId |
| `VersionRef_universe` | `r_version_ref_universe` | UniverseId, VersionRef_universe_v1 |
| `VersionRef_universe_v1` | `r_version_ref_universe_v1` (scalar column) | null |
| `RecordVersionId` | `r_record_version_id` (scalar column) | string |
| `EvidenceBasis_v4_evaluator` | `r_evidence_basis_v4_evaluator` | EvidenceBasis_v4_evaluator_v0, EvidenceBasis_v4_evaluator_v1 |
| `EvidenceBasis_v4_evaluator_v0` | `r_evidence_basis_v4_evaluator_v0` (scalar column) | string |
| `EvidenceBasis_v4_evaluator_v1` | `r_evidence_basis_v4_evaluator_v1` (scalar column) | null |
| `EvidenceBasis_v4_kind` | `r_evidence_basis_v4_kind` (scalar column) | string |
| `AttributeAssertionV3_establishedBy` | `r_attribute_assertion_v3_established_by` | EventEffectRef, AttributeAssertionV3_establishedBy_v1 |
| `EventEffectRef` | `r_event_effect_ref` | event → RecordRef, slot → EventEffectRef_slot |
| `EventEffectRef_slot` | `r_event_effect_ref_slot` (scalar column) | string |
| `AttributeAssertionV3_establishedBy_v1` | `r_attribute_assertion_v3_established_by_v1` (scalar column) | null |
| `AttributeAssertionV3_attributeMode` | `r_attribute_assertion_v3_attribute_mode` (scalar column) | string |
| `Payload` | `r_payload` | Payload_v0, Payload_v1, Payload_v2, Payload_v3, Payload_v4, Payload_v5, Payload_v6, Payload_v7, Payload_v8, Payload_v9, Payload_v10, Payload_v11, Payload_v12, Payload_v13, Payload_v14, Payload_v15, Payload_v16, Payload_v17, Payload_v18, Payload_v19, Payload_v20, Payload_v21, Payload_v22, Payload_v23, Payload_v24, Payload_v25, Payload_v26, Payload_v27, Payload_v28, Payload_v29, Payload_v30, Payload_v31, Payload_v32, Payload_v33, Payload_v34, Payload_v35, Payload_v36, Payload_v37 |
| `Payload_v0` | `r_payload_v0` | names → Payload_v0_names, types → Payload_v0_types, worldAssociations → Payload_v0_worldAssociations, labels → Payload_v0_labels, metadata → Payload_v0_metadata, record_kind → Payload_v0_record_kind |
| `Payload_v0_names` | `r_payload_v0_names` | ContextualName |
| `Payload_v0_types` | `r_payload_v0_types` | RecordId |
| `Payload_v0_worldAssociations` | `r_payload_v0_world_associations` | WorldAssociation |
| `Payload_v0_labels` | `r_payload_v0_labels` | Payload_v0_labels_item |
| `Payload_v0_labels_item` | `r_payload_v0_labels_item` (scalar column) | string |
| `Payload_v0_metadata` | `r_payload_v0_metadata` | Value |
| `Payload_v0_record_kind` | `r_payload_v0_record_kind` (scalar column) | string |
| `Payload_v1` | `r_payload_v1` | target → AppearanceTarget, label → Payload_v1_label, physical_description → Payload_v1_physical_description, atmosphere → Payload_v1_atmosphere, images → Payload_v1_images, links → Payload_v1_links, validity → Validity, record_kind → Payload_v1_record_kind |
| `AppearanceTarget` | `r_appearance_target` | AppearanceTarget_v0, AppearanceTarget_v1 |
| `AppearanceTarget_v0` | `r_appearance_target_v0` | kind → AppearanceTarget_v0_kind |
| `AppearanceTarget_v0_kind` | `r_appearance_target_v0_kind` (scalar column) | string |
| `AppearanceTarget_v1` | `r_appearance_target_v1` | entry → RecordRef, kind → AppearanceTarget_v1_kind |
| `AppearanceTarget_v1_kind` | `r_appearance_target_v1_kind` (scalar column) | string |
| `Payload_v1_label` | `r_payload_v1_label` (scalar column) | string |
| `Payload_v1_physical_description` | `r_payload_v1_physical_description` (scalar column) | string |
| `Payload_v1_atmosphere` | `r_payload_v1_atmosphere` (scalar column) | string |
| `Payload_v1_images` | `r_payload_v1_images` | AppearanceImage |
| `AppearanceImage` | `r_appearance_image` | asset → RecordRef, caption → AppearanceImage_caption, purpose → ImagePurpose |
| `AppearanceImage_caption` | `r_appearance_image_caption` (scalar column) | string |
| `ImagePurpose` | `r_image_purpose` (scalar column) | string |
| `Payload_v1_links` | `r_payload_v1_links` | AppearanceLink |
| `AppearanceLink` | `r_appearance_link` | entry → RecordRef, relationship → AppearanceRelationship, note → AppearanceLink_note |
| `AppearanceRelationship` | `r_appearance_relationship` (scalar column) | string |
| `AppearanceLink_note` | `r_appearance_link_note` (scalar column) | string |
| `Payload_v1_record_kind` | `r_payload_v1_record_kind` (scalar column) | string |
| `Payload_v2` | `r_payload_v2` | digest → Payload_v2_digest, media_type → Payload_v2_media_type, byte_size → Payload_v2_byte_size, width → Payload_v2_width, height → Payload_v2_height, original_name → Payload_v2_original_name, record_kind → Payload_v2_record_kind |
| `Payload_v2_digest` | `r_payload_v2_digest` (scalar column) | string |
| `Payload_v2_media_type` | `r_payload_v2_media_type` (scalar column) | string |
| `Payload_v2_byte_size` | `r_payload_v2_byte_size` (scalar column) | integer |
| `Payload_v2_width` | `r_payload_v2_width` (scalar column) | integer |
| `Payload_v2_height` | `r_payload_v2_height` (scalar column) | integer |
| `Payload_v2_original_name` | `r_payload_v2_original_name` (scalar column) | string |
| `Payload_v2_record_kind` | `r_payload_v2_record_kind` (scalar column) | string |
| `Payload_v3` | `r_payload_v3` | selector → Payload_v3_selector, aliases → Payload_v3_aliases, settingType → Payload_v3_settingType, labels → Payload_v3_labels, metadata → Payload_v3_metadata, record_kind → Payload_v3_record_kind |
| `Payload_v3_selector` | `r_payload_v3_selector` (scalar column) | string |
| `Payload_v3_aliases` | `r_payload_v3_aliases` | Payload_v3_aliases_item |
| `Payload_v3_aliases_item` | `r_payload_v3_aliases_item` (scalar column) | string |
| `Payload_v3_settingType` | `r_payload_v3_setting_type` | Payload_v3_settingType_v0, Payload_v3_settingType_v1 |
| `Payload_v3_settingType_v0` | `r_payload_v3_setting_type_v0` (scalar column) | string |
| `Payload_v3_settingType_v1` | `r_payload_v3_setting_type_v1` (scalar column) | null |
| `Payload_v3_labels` | `r_payload_v3_labels` | Payload_v3_labels_item |
| `Payload_v3_labels_item` | `r_payload_v3_labels_item` (scalar column) | string |
| `Payload_v3_metadata` | `r_payload_v3_metadata` | Value |
| `Payload_v3_record_kind` | `r_payload_v3_record_kind` (scalar column) | string |
| `Payload_v4` | `r_payload_v4` | labels → Payload_v4_labels, metadata → Payload_v4_metadata, record_kind → Payload_v4_record_kind |
| `Payload_v4_labels` | `r_payload_v4_labels` | Payload_v4_labels_item |
| `Payload_v4_labels_item` | `r_payload_v4_labels_item` (scalar column) | string |
| `Payload_v4_metadata` | `r_payload_v4_metadata` | Value |
| `Payload_v4_record_kind` | `r_payload_v4_record_kind` (scalar column) | string |
| `Payload_v5` | `r_payload_v5` | kind → WorkKind, title → Payload_v5_title, labels → Payload_v5_labels, sourceRefs → Payload_v5_sourceRefs, versions → Payload_v5_versions, worldAssociations → Payload_v5_worldAssociations, record_kind → Payload_v5_record_kind |
| `WorkKind` | `r_work_kind` | WorkKind_v0, WorkKind_v1 |
| `WorkKind_v0` | `r_work_kind_v0` (scalar column) | string |
| `WorkKind_v1` | `r_work_kind_v1` (scalar column) | string |
| `Payload_v5_title` | `r_payload_v5_title` (scalar column) | string |
| `Payload_v5_labels` | `r_payload_v5_labels` | Payload_v5_labels_item |
| `Payload_v5_labels_item` | `r_payload_v5_labels_item` (scalar column) | string |
| `Payload_v5_sourceRefs` | `r_payload_v5_source_refs` | RecordRef |
| `Payload_v5_versions` | `r_payload_v5_versions` | RecordId |
| `Payload_v5_worldAssociations` | `r_payload_v5_world_associations` | WorldAssociation |
| `Payload_v5_record_kind` | `r_payload_v5_record_kind` (scalar column) | string |
| `Payload_v6` | `r_payload_v6` | work → RecordRef, versionLabel → Payload_v6_versionLabel, binding → WorkBinding, record_kind → Payload_v6_record_kind |
| `Payload_v6_versionLabel` | `r_payload_v6_version_label` (scalar column) | string |
| `WorkBinding` | `r_work_binding` | WorkBinding_v0, WorkBinding_v1, WorkBinding_v2 |
| `WorkBinding_v0` | `r_work_binding_v0` | continuity → ContinuityId, revision → RevisionId, kind → WorkBinding_v0_kind |
| `ContinuityId` | `r_continuity_id` (scalar column) | string |
| `RevisionId` | `r_revision_id` (scalar column) | string |
| `WorkBinding_v0_kind` | `r_work_binding_v0_kind` (scalar column) | string |
| `WorkBinding_v1` | `r_work_binding_v1` | kind → WorkBinding_v1_kind |
| `WorkBinding_v1_kind` | `r_work_binding_v1_kind` (scalar column) | string |
| `WorkBinding_v2` | `r_work_binding_v2` | segments → WorkBinding_v2_segments, kind → WorkBinding_v2_kind |
| `WorkBinding_v2_segments` | `r_work_binding_v2_segments` | WorkSegment |
| `WorkSegment` | `r_work_segment` | segment → WorkSegment_segment, continuity → ContinuityId, revision → RevisionId |
| `WorkSegment_segment` | `r_work_segment_segment` (scalar column) | string |
| `WorkBinding_v2_kind` | `r_work_binding_v2_kind` (scalar column) | string |
| `Payload_v6_record_kind` | `r_payload_v6_record_kind` (scalar column) | string |
| `Payload_v7` | `r_payload_v7` | workVersion → VersionRef, sceneId → Payload_v7_sceneId, disclosedRecords → Payload_v7_disclosedRecords, viewpoint → Payload_v7_viewpoint, narrativePosition → Payload_v7_narrativePosition, depictedEvents → Payload_v7_depictedEvents, narrationFrame → Payload_v7_narrationFrame, worldAssociations → Payload_v7_worldAssociations, record_kind → Payload_v7_record_kind |
| `Payload_v7_sceneId` | `r_payload_v7_scene_id` (scalar column) | string |
| `Payload_v7_disclosedRecords` | `r_payload_v7_disclosed_records` | RecordRef |
| `Payload_v7_viewpoint` | `r_payload_v7_viewpoint` | RecordRef, Payload_v7_viewpoint_v1 |
| `Payload_v7_viewpoint_v1` | `r_payload_v7_viewpoint_v1` (scalar column) | null |
| `Payload_v7_narrativePosition` | `r_payload_v7_narrative_position` | Payload_v7_narrativePosition_v0, Payload_v7_narrativePosition_v1 |
| `Payload_v7_narrativePosition_v0` | `r_payload_v7_narrative_position_v0` (scalar column) | integer |
| `Payload_v7_narrativePosition_v1` | `r_payload_v7_narrative_position_v1` (scalar column) | null |
| `Payload_v7_depictedEvents` | `r_payload_v7_depicted_events` | RecordRef |
| `Payload_v7_narrationFrame` | `r_payload_v7_narration_frame` | RecordRef, Payload_v7_narrationFrame_v1 |
| `Payload_v7_narrationFrame_v1` | `r_payload_v7_narration_frame_v1` (scalar column) | null |
| `Payload_v7_worldAssociations` | `r_payload_v7_world_associations` | WorldAssociation |
| `Payload_v7_record_kind` | `r_payload_v7_record_kind` (scalar column) | string |
| `Payload_v8` | `r_payload_v8` | workVersion → VersionRef, passageId → Payload_v8_passageId, anchor → Payload_v8_anchor, record_kind → Payload_v8_record_kind |
| `Payload_v8_passageId` | `r_payload_v8_passage_id` (scalar column) | string |
| `Payload_v8_anchor` | `r_payload_v8_anchor` | RecordRef, Payload_v8_anchor_v1 |
| `Payload_v8_anchor_v1` | `r_payload_v8_anchor_v1` (scalar column) | null |
| `Payload_v8_record_kind` | `r_payload_v8_record_kind` (scalar column) | string |
| `Payload_v9` | `r_payload_v9` | title → Payload_v9_title, labels → Payload_v9_labels, memberships → Payload_v9_memberships, record_kind → Payload_v9_record_kind |
| `Payload_v9_title` | `r_payload_v9_title` (scalar column) | string |
| `Payload_v9_labels` | `r_payload_v9_labels` | Payload_v9_labels_item |
| `Payload_v9_labels_item` | `r_payload_v9_labels_item` (scalar column) | string |
| `Payload_v9_memberships` | `r_payload_v9_memberships` | SagaMembership |
| `SagaMembership` | `r_saga_membership` | work → RecordRef, role → SagaMembership_role, order → SagaMembership_order |
| `SagaMembership_role` | `r_saga_membership_role` (scalar column) | string |
| `SagaMembership_order` | `r_saga_membership_order` | SagaMembership_order_v0, SagaMembership_order_v1 |
| `SagaMembership_order_v0` | `r_saga_membership_order_v0` (scalar column) | integer |
| `SagaMembership_order_v1` | `r_saga_membership_order_v1` (scalar column) | null |
| `Payload_v9_record_kind` | `r_payload_v9_record_kind` (scalar column) | string |
| `Payload_v10` | `r_payload_v10` | namespace → Payload_v10_namespace, key → Payload_v10_key, labels → Payload_v10_labels, parents → Payload_v10_parents, classificationExecutable → Payload_v10_classificationExecutable, record_kind → Payload_v10_record_kind |
| `Payload_v10_namespace` | `r_payload_v10_namespace` (scalar column) | string |
| `Payload_v10_key` | `r_payload_v10_key` (scalar column) | string |
| `Payload_v10_labels` | `r_payload_v10_labels` | Payload_v10_labels_item |
| `Payload_v10_labels_item` | `r_payload_v10_labels_item` (scalar column) | string |
| `Payload_v10_parents` | `r_payload_v10_parents` | RecordId |
| `Payload_v10_classificationExecutable` | `r_payload_v10_classification_executable` (scalar column) | boolean |
| `Payload_v10_record_kind` | `r_payload_v10_record_kind` (scalar column) | string |
| `Payload_v11` | `r_payload_v11` | namespace → Payload_v11_namespace, key → Payload_v11_key, labels → Payload_v11_labels, subjectTypes → Payload_v11_subjectTypes, value → ValueShape, multiplicity → Multiplicity, unitDimension → Payload_v11_unitDimension, persistence → PersistenceSemantics, exclusive → Payload_v11_exclusive, inverse → Payload_v11_inverse, symmetric → Payload_v11_symmetric, transitive → Payload_v11_transitive, record_kind → Payload_v11_record_kind |
| `Payload_v11_namespace` | `r_payload_v11_namespace` (scalar column) | string |
| `Payload_v11_key` | `r_payload_v11_key` (scalar column) | string |
| `Payload_v11_labels` | `r_payload_v11_labels` | Payload_v11_labels_item |
| `Payload_v11_labels_item` | `r_payload_v11_labels_item` (scalar column) | string |
| `Payload_v11_subjectTypes` | `r_payload_v11_subject_types` | RecordId |
| `ValueShape` | `r_value_shape` | ValueShape_v0, ValueShape_v1, ValueShape_v2, ValueShape_v3, ValueShape_v4, ValueShape_v5, ValueShape_v6, ValueShape_v7, ValueShape_v8, ValueShape_v9, ValueShape_v10, ValueShape_v11, ValueShape_v12, ValueShape_v13 |
| `ValueShape_v0` | `r_value_shape_v0` | kind → ValueShape_v0_kind |
| `ValueShape_v0_kind` | `r_value_shape_v0_kind` (scalar column) | string |
| `ValueShape_v1` | `r_value_shape_v1` | kind → ValueShape_v1_kind |
| `ValueShape_v1_kind` | `r_value_shape_v1_kind` (scalar column) | string |
| `ValueShape_v2` | `r_value_shape_v2` | kind → ValueShape_v2_kind |
| `ValueShape_v2_kind` | `r_value_shape_v2_kind` (scalar column) | string |
| `ValueShape_v3` | `r_value_shape_v3` | kind → ValueShape_v3_kind |
| `ValueShape_v3_kind` | `r_value_shape_v3_kind` (scalar column) | string |
| `ValueShape_v4` | `r_value_shape_v4` | kind → ValueShape_v4_kind |
| `ValueShape_v4_kind` | `r_value_shape_v4_kind` (scalar column) | string |
| `ValueShape_v5` | `r_value_shape_v5` | unit → UnitId, kind → ValueShape_v5_kind |
| `ValueShape_v5_kind` | `r_value_shape_v5_kind` (scalar column) | string |
| `ValueShape_v6` | `r_value_shape_v6` | unit → ValueShape_v6_unit, kind → ValueShape_v6_kind |
| `ValueShape_v6_unit` | `r_value_shape_v6_unit` | UnitId, ValueShape_v6_unit_v1 |
| `ValueShape_v6_unit_v1` | `r_value_shape_v6_unit_v1` (scalar column) | null |
| `ValueShape_v6_kind` | `r_value_shape_v6_kind` (scalar column) | string |
| `ValueShape_v7` | `r_value_shape_v7` | subject_types → ValueShape_v7_subject_types, kind → ValueShape_v7_kind |
| `ValueShape_v7_subject_types` | `r_value_shape_v7_subject_types` | RecordId |
| `ValueShape_v7_kind` | `r_value_shape_v7_kind` (scalar column) | string |
| `ValueShape_v8` | `r_value_shape_v8` | kind → ValueShape_v8_kind |
| `ValueShape_v8_kind` | `r_value_shape_v8_kind` (scalar column) | string |
| `ValueShape_v9` | `r_value_shape_v9` | kind → ValueShape_v9_kind |
| `ValueShape_v9_kind` | `r_value_shape_v9_kind` (scalar column) | string |
| `ValueShape_v10` | `r_value_shape_v10` | definition → ValueDefinitionId, kind → ValueShape_v10_kind |
| `ValueShape_v10_kind` | `r_value_shape_v10_kind` (scalar column) | string |
| `ValueShape_v11` | `r_value_shape_v11` | item → ValueShape, kind → ValueShape_v11_kind |
| `ValueShape_v11_kind` | `r_value_shape_v11_kind` (scalar column) | string |
| `ValueShape_v12` | `r_value_shape_v12` | definition → ValueDefinitionId, kind → ValueShape_v12_kind |
| `ValueShape_v12_kind` | `r_value_shape_v12_kind` (scalar column) | string |
| `ValueShape_v13` | `r_value_shape_v13` | kind → ValueShape_v13_kind |
| `ValueShape_v13_kind` | `r_value_shape_v13_kind` (scalar column) | string |
| `Multiplicity` | `r_multiplicity` (scalar column) | string |
| `Payload_v11_unitDimension` | `r_payload_v11_unit_dimension` | Payload_v11_unitDimension_v0, Payload_v11_unitDimension_v1 |
| `Payload_v11_unitDimension_v0` | `r_payload_v11_unit_dimension_v0` (scalar column) | string |
| `Payload_v11_unitDimension_v1` | `r_payload_v11_unit_dimension_v1` (scalar column) | null |
| `Payload_v11_exclusive` | `r_payload_v11_exclusive` (scalar column) | boolean |
| `Payload_v11_inverse` | `r_payload_v11_inverse` | Payload_v11_inverse_v0, Payload_v11_inverse_v1 |
| `Payload_v11_inverse_v0` | `r_payload_v11_inverse_v0` (scalar column) | string |
| `Payload_v11_inverse_v1` | `r_payload_v11_inverse_v1` (scalar column) | null |
| `Payload_v11_symmetric` | `r_payload_v11_symmetric` (scalar column) | boolean |
| `Payload_v11_transitive` | `r_payload_v11_transitive` (scalar column) | boolean |
| `Payload_v11_record_kind` | `r_payload_v11_record_kind` (scalar column) | string |
| `Payload_v12` | `r_payload_v12` | namespace → Payload_v12_namespace, key → Payload_v12_key, labels → Payload_v12_labels, roles → Payload_v12_roles, record_kind → Payload_v12_record_kind |
| `Payload_v12_namespace` | `r_payload_v12_namespace` (scalar column) | string |
| `Payload_v12_key` | `r_payload_v12_key` (scalar column) | string |
| `Payload_v12_labels` | `r_payload_v12_labels` | Payload_v12_labels_item |
| `Payload_v12_labels_item` | `r_payload_v12_labels_item` (scalar column) | string |
| `Payload_v12_roles` | `r_payload_v12_roles` | RoleDef |
| `RoleDef` | `r_role_def` | name → RoleDef_name, participantTypes → RoleDef_participantTypes, multiplicity → Multiplicity, ordered → RoleDef_ordered |
| `RoleDef_name` | `r_role_def_name` (scalar column) | string |
| `RoleDef_participantTypes` | `r_role_def_participant_types` | RecordId |
| `RoleDef_ordered` | `r_role_def_ordered` (scalar column) | boolean |
| `Payload_v12_record_kind` | `r_payload_v12_record_kind` (scalar column) | string |
| `Payload_v13` | `r_payload_v13` | namespace → Payload_v13_namespace, key → Payload_v13_key, dimension → Payload_v13_dimension, symbol → Payload_v13_symbol, labels → Payload_v13_labels, scaleToBase → Payload_v13_scaleToBase, base → Payload_v13_base, validity → Validity, record_kind → Payload_v13_record_kind |
| `Payload_v13_namespace` | `r_payload_v13_namespace` (scalar column) | string |
| `Payload_v13_key` | `r_payload_v13_key` (scalar column) | string |
| `Payload_v13_dimension` | `r_payload_v13_dimension` (scalar column) | string |
| `Payload_v13_symbol` | `r_payload_v13_symbol` (scalar column) | string |
| `Payload_v13_labels` | `r_payload_v13_labels` | Payload_v13_labels_item |
| `Payload_v13_labels_item` | `r_payload_v13_labels_item` (scalar column) | string |
| `Payload_v13_scaleToBase` | `r_payload_v13_scale_to_base` | Value, Payload_v13_scaleToBase_v1 |
| `Payload_v13_scaleToBase_v1` | `r_payload_v13_scale_to_base_v1` (scalar column) | null |
| `Payload_v13_base` | `r_payload_v13_base` | UnitId, Payload_v13_base_v1 |
| `Payload_v13_base_v1` | `r_payload_v13_base_v1` (scalar column) | null |
| `Payload_v13_record_kind` | `r_payload_v13_record_kind` (scalar column) | string |
| `Payload_v14` | `r_payload_v14` | namespace → Payload_v14_namespace, key → Payload_v14_key, labels → Payload_v14_labels, epoch → Payload_v14_epoch, unitStructure → Payload_v14_unitStructure, conversions → Payload_v14_conversions, record_kind → Payload_v14_record_kind |
| `Payload_v14_namespace` | `r_payload_v14_namespace` (scalar column) | string |
| `Payload_v14_key` | `r_payload_v14_key` (scalar column) | string |
| `Payload_v14_labels` | `r_payload_v14_labels` | Payload_v14_labels_item |
| `Payload_v14_labels_item` | `r_payload_v14_labels_item` (scalar column) | string |
| `Payload_v14_epoch` | `r_payload_v14_epoch` | Payload_v14_epoch_v0, Payload_v14_epoch_v1 |
| `Payload_v14_epoch_v0` | `r_payload_v14_epoch_v0` (scalar column) | string |
| `Payload_v14_epoch_v1` | `r_payload_v14_epoch_v1` (scalar column) | null |
| `Payload_v14_unitStructure` | `r_payload_v14_unit_structure` | Payload_v14_unitStructure_item |
| `Payload_v14_unitStructure_item` | `r_payload_v14_unit_structure_item` (scalar column) | string |
| `Payload_v14_conversions` | `r_payload_v14_conversions` | CalendarConversion |
| `CalendarConversion` | `r_calendar_conversion` | target → CalendarId, expression → CalendarConversion_expression, valid → CalendarConversion_valid |
| `CalendarConversion_expression` | `r_calendar_conversion_expression` | CalendarConversion_expression_v0, CalendarConversion_expression_v1 |
| `CalendarConversion_expression_v0` | `r_calendar_conversion_expression_v0` (scalar column) | string |
| `CalendarConversion_expression_v1` | `r_calendar_conversion_expression_v1` (scalar column) | null |
| `CalendarConversion_valid` | `r_calendar_conversion_valid` (scalar column) | boolean |
| `Payload_v14_record_kind` | `r_payload_v14_record_kind` (scalar column) | string |
| `Payload_v15` | `r_payload_v15` | namespace → Payload_v15_namespace, key → Payload_v15_key, labels → Payload_v15_labels, fields → Payload_v15_fields, record_kind → Payload_v15_record_kind |
| `Payload_v15_namespace` | `r_payload_v15_namespace` (scalar column) | string |
| `Payload_v15_key` | `r_payload_v15_key` (scalar column) | string |
| `Payload_v15_labels` | `r_payload_v15_labels` | Payload_v15_labels_item |
| `Payload_v15_labels_item` | `r_payload_v15_labels_item` (scalar column) | string |
| `Payload_v15_fields` | `r_payload_v15_fields` | ValueDefField |
| `ValueDefField` | `r_value_def_field` | name → ValueDefField_name, shape → ValueShape, required → ValueDefField_required, allowsUnknown → ValueDefField_allowsUnknown |
| `ValueDefField_name` | `r_value_def_field_name` (scalar column) | string |
| `ValueDefField_required` | `r_value_def_field_required` (scalar column) | boolean |
| `ValueDefField_allowsUnknown` | `r_value_def_field_allows_unknown` (scalar column) | boolean |
| `Payload_v15_record_kind` | `r_payload_v15_record_kind` (scalar column) | string |
| `Payload_v16` | `r_payload_v16` | key → Payload_v16_key, version → Payload_v16_version, dependencies → Payload_v16_dependencies, capabilities → Payload_v16_capabilities, records → Payload_v16_records, record_kind → Payload_v16_record_kind |
| `Payload_v16_key` | `r_payload_v16_key` (scalar column) | string |
| `Payload_v16_version` | `r_payload_v16_version` (scalar column) | string |
| `Payload_v16_dependencies` | `r_payload_v16_dependencies` | Payload_v16_dependencies_item |
| `Payload_v16_dependencies_item` | `r_payload_v16_dependencies_item` (scalar column) | string |
| `Payload_v16_capabilities` | `r_payload_v16_capabilities` | Payload_v16_capabilities_item |
| `Payload_v16_capabilities_item` | `r_payload_v16_capabilities_item` (scalar column) | string |
| `Payload_v16_records` | `r_payload_v16_records` | RecordId |
| `Payload_v16_record_kind` | `r_payload_v16_record_kind` (scalar column) | string |
| `Payload_v17` | `r_payload_v17` | predicate → RecordRef, subject → RecordRef, roles → Payload_v17_roles, value → Payload_v17_value, quantification → Quantification, context → RecordRef, record_kind → Payload_v17_record_kind |
| `Payload_v17_roles` | `r_payload_v17_roles` | PropositionRole |
| `PropositionRole` | `r_proposition_role` | role → PropositionRole_role, participant → RecordRef |
| `PropositionRole_role` | `r_proposition_role_role` (scalar column) | string |
| `Payload_v17_value` | `r_payload_v17_value` | Value, Payload_v17_value_v1 |
| `Payload_v17_value_v1` | `r_payload_v17_value_v1` (scalar column) | null |
| `Quantification` | `r_quantification` | Quantification_v0, Quantification_v1, Quantification_v2 |
| `Quantification_v0` | `r_quantification_v0` (scalar column) | string |
| `Quantification_v1` | `r_quantification_v1` (scalar column) | string |
| `Quantification_v2` | `r_quantification_v2` (scalar column) | string |
| `Payload_v17_record_kind` | `r_payload_v17_record_kind` (scalar column) | string |
| `Payload_v18` | `r_payload_v18` | proposition → RecordRef, polarity → Polarity, scope → Scope, validity → Validity, persistence → PersistenceSemantics, precision → Precision, alternatives → Payload_v18_alternatives, basis → EvidenceBasis, establishedBy → Payload_v18_establishedBy, record_kind → Payload_v18_record_kind |
| `Payload_v18_alternatives` | `r_payload_v18_alternatives` | Value |
| `Payload_v18_establishedBy` | `r_payload_v18_established_by` | EventEffectRef, Payload_v18_establishedBy_v1 |
| `Payload_v18_establishedBy_v1` | `r_payload_v18_established_by_v1` (scalar column) | null |
| `Payload_v18_record_kind` | `r_payload_v18_record_kind` (scalar column) | string |
| `Payload_v19` | `r_payload_v19` | universe → UniverseId, kind → RepresentedContextKind, parent → Payload_v19_parent, chronology → Payload_v19_chronology, labels → Payload_v19_labels, record_kind → Payload_v19_record_kind |
| `RepresentedContextKind` | `r_represented_context_kind` | RepresentedContextKind_v0, RepresentedContextKind_v1, RepresentedContextKind_v2, RepresentedContextKind_v3, RepresentedContextKind_v4 |
| `RepresentedContextKind_v0` | `r_represented_context_kind_v0` | kind → RepresentedContextKind_v0_kind |
| `RepresentedContextKind_v0_kind` | `r_represented_context_kind_v0_kind` (scalar column) | string |
| `RepresentedContextKind_v1` | `r_represented_context_kind_v1` | holder → RecordRef, kind → RepresentedContextKind_v1_kind |
| `RepresentedContextKind_v1_kind` | `r_represented_context_kind_v1_kind` (scalar column) | string |
| `RepresentedContextKind_v2` | `r_represented_context_kind_v2` | source → RecordRef, kind → RepresentedContextKind_v2_kind |
| `RepresentedContextKind_v2_kind` | `r_represented_context_kind_v2_kind` (scalar column) | string |
| `RepresentedContextKind_v3` | `r_represented_context_kind_v3` | narrator → RecordRef, kind → RepresentedContextKind_v3_kind |
| `RepresentedContextKind_v3_kind` | `r_represented_context_kind_v3_kind` (scalar column) | string |
| `RepresentedContextKind_v4` | `r_represented_context_kind_v4` | label → RepresentedContextKind_v4_label, kind → RepresentedContextKind_v4_kind |
| `RepresentedContextKind_v4_label` | `r_represented_context_kind_v4_label` (scalar column) | string |
| `RepresentedContextKind_v4_kind` | `r_represented_context_kind_v4_kind` (scalar column) | string |
| `Payload_v19_parent` | `r_payload_v19_parent` | RecordRef, Payload_v19_parent_v1 |
| `Payload_v19_parent_v1` | `r_payload_v19_parent_v1` (scalar column) | null |
| `Payload_v19_chronology` | `r_payload_v19_chronology` | Chronology, Payload_v19_chronology_v1 |
| `Chronology` | `r_chronology` | calendar → CalendarId, system → ClockSystem, first_interaction → Chronology_first_interaction, current → Chronology_current |
| `ClockSystem` | `r_clock_system` | ClockSystem_v0, ClockSystem_v1 |
| `ClockSystem_v0` | `r_clock_system_v0` | offset_seconds → ClockSystem_v0_offset_seconds, kind → ClockSystem_v0_kind |
| `ClockSystem_v0_offset_seconds` | `r_clock_system_v0_offset_seconds` (scalar column) | integer |
| `ClockSystem_v0_kind` | `r_clock_system_v0_kind` (scalar column) | string |
| `ClockSystem_v1` | `r_clock_system_v1` | tick_label → ClockSystem_v1_tick_label, ticks_per_month → ClockSystem_v1_ticks_per_month, kind → ClockSystem_v1_kind |
| `ClockSystem_v1_tick_label` | `r_clock_system_v1_tick_label` (scalar column) | string |
| `ClockSystem_v1_ticks_per_month` | `r_clock_system_v1_ticks_per_month` | ClockSystem_v1_ticks_per_month_v0, ClockSystem_v1_ticks_per_month_v1 |
| `ClockSystem_v1_ticks_per_month_v0` | `r_clock_system_v1_ticks_per_month_v0` (scalar column) | integer |
| `ClockSystem_v1_ticks_per_month_v1` | `r_clock_system_v1_ticks_per_month_v1` (scalar column) | null |
| `ClockSystem_v1_kind` | `r_clock_system_v1_kind` (scalar column) | string |
| `Chronology_first_interaction` | `r_chronology_first_interaction` (scalar column) | string |
| `Chronology_current` | `r_chronology_current` (scalar column) | string |
| `Payload_v19_chronology_v1` | `r_payload_v19_chronology_v1` (scalar column) | null |
| `Payload_v19_labels` | `r_payload_v19_labels` | Payload_v19_labels_item |
| `Payload_v19_labels_item` | `r_payload_v19_labels_item` (scalar column) | string |
| `Payload_v19_record_kind` | `r_payload_v19_record_kind` (scalar column) | string |
| `Payload_v20` | `r_payload_v20` | subject → RecordRef, predicate → Payload_v20_predicate, members → Payload_v20_members, completeness → CompletenessKind, validity → Validity, scope → Scope, record_kind → Payload_v20_record_kind |
| `Payload_v20_predicate` | `r_payload_v20_predicate` (scalar column) | string |
| `Payload_v20_members` | `r_payload_v20_members` | RecordRef |
| `CompletenessKind` | `r_completeness_kind` | CompletenessKind_v0, CompletenessKind_v1 |
| `CompletenessKind_v0` | `r_completeness_kind_v0` (scalar column) | string |
| `CompletenessKind_v1` | `r_completeness_kind_v1` | observer_known → CompletenessKind_v1_observer_known |
| `CompletenessKind_v1_observer_known` | `r_completeness_kind_v1_observer_known` | observer → RecordId |
| `Payload_v20_record_kind` | `r_payload_v20_record_kind` (scalar column) | string |
| `Payload_v21` | `r_payload_v21` | key → Payload_v21_key, area → BoundaryArea, mode → BoundaryMode, constraints → Payload_v21_constraints, validity → Validity, scope → Scope, record_kind → Payload_v21_record_kind |
| `Payload_v21_key` | `r_payload_v21_key` (scalar column) | string |
| `BoundaryArea` | `r_boundary_area` | BoundaryArea_v0, BoundaryArea_v1, BoundaryArea_v2 |
| `BoundaryArea_v0` | `r_boundary_area_v0` | universe → BoundaryArea_v0_universe, record → RecordId, kind → BoundaryArea_v0_kind |
| `BoundaryArea_v0_universe` | `r_boundary_area_v0_universe` | UniverseId, BoundaryArea_v0_universe_v1 |
| `BoundaryArea_v0_universe_v1` | `r_boundary_area_v0_universe_v1` (scalar column) | null |
| `BoundaryArea_v0_kind` | `r_boundary_area_v0_kind` (scalar column) | string |
| `BoundaryArea_v1` | `r_boundary_area_v1` | predicate → BoundaryArea_v1_predicate, subject → BoundaryArea_v1_subject, kind → BoundaryArea_v1_kind |
| `BoundaryArea_v1_predicate` | `r_boundary_area_v1_predicate` (scalar column) | string |
| `BoundaryArea_v1_subject` | `r_boundary_area_v1_subject` | RecordRef, BoundaryArea_v1_subject_v1 |
| `BoundaryArea_v1_subject_v1` | `r_boundary_area_v1_subject_v1` (scalar column) | null |
| `BoundaryArea_v1_kind` | `r_boundary_area_v1_kind` (scalar column) | string |
| `BoundaryArea_v2` | `r_boundary_area_v2` | entity_type → RecordId, kind → BoundaryArea_v2_kind |
| `BoundaryArea_v2_kind` | `r_boundary_area_v2_kind` (scalar column) | string |
| `BoundaryMode` | `r_boundary_mode` | BoundaryMode_v0, BoundaryMode_v1, BoundaryMode_v2, BoundaryMode_v3, BoundaryMode_v4, BoundaryMode_v5 |
| `BoundaryMode_v0` | `r_boundary_mode_v0` (scalar column) | string |
| `BoundaryMode_v1` | `r_boundary_mode_v1` (scalar column) | string |
| `BoundaryMode_v2` | `r_boundary_mode_v2` (scalar column) | string |
| `BoundaryMode_v3` | `r_boundary_mode_v3` (scalar column) | string |
| `BoundaryMode_v4` | `r_boundary_mode_v4` (scalar column) | string |
| `BoundaryMode_v5` | `r_boundary_mode_v5` (scalar column) | string |
| `Payload_v21_constraints` | `r_payload_v21_constraints` | Expr |
| `Expr` | `r_expr` | Expr_v0, Expr_v1, Expr_v2, Expr_v3, Expr_v4, Expr_v5, Expr_v6, Expr_v7, Expr_v8, Expr_v9, Expr_v10, Expr_v11, Expr_v12, Expr_v13, Expr_v14 |
| `Expr_v0` | `r_expr_v0` | subject → Operand, predicate → Expr_v0_predicate, context → Operand, kind → Expr_v0_kind |
| `Operand` | `r_operand` | Operand_v0, Operand_v1, Operand_v2, Operand_v3, Operand_v4, Operand_v5 |
| `Operand_v0` | `r_operand_v0` | name → Operand_v0_name, kind → Operand_v0_kind |
| `Operand_v0_name` | `r_operand_v0_name` (scalar column) | string |
| `Operand_v0_kind` | `r_operand_v0_kind` (scalar column) | string |
| `Operand_v1` | `r_operand_v1` | ref → RecordRef, kind → Operand_v1_kind |
| `Operand_v1_kind` | `r_operand_v1_kind` (scalar column) | string |
| `Operand_v2` | `r_operand_v2` | value → Value, kind → Operand_v2_kind |
| `Operand_v2_kind` | `r_operand_v2_kind` (scalar column) | string |
| `Operand_v3` | `r_operand_v3` | kind → Operand_v3_kind |
| `Operand_v3_kind` | `r_operand_v3_kind` (scalar column) | string |
| `Operand_v4` | `r_operand_v4` | role → Operand_v4_role, kind → Operand_v4_kind |
| `Operand_v4_role` | `r_operand_v4_role` (scalar column) | string |
| `Operand_v4_kind` | `r_operand_v4_kind` (scalar column) | string |
| `Operand_v5` | `r_operand_v5` | kind → Operand_v5_kind |
| `Operand_v5_kind` | `r_operand_v5_kind` (scalar column) | string |
| `Expr_v0_predicate` | `r_expr_v0_predicate` (scalar column) | string |
| `Expr_v0_kind` | `r_expr_v0_kind` (scalar column) | string |
| `Expr_v1` | `r_expr_v1` | holder → RecordRef, proposition → RecordRef, attitude → EpistemicAttitudeKind, kind → Expr_v1_kind |
| `EpistemicAttitudeKind` | `r_epistemic_attitude_kind` (scalar column) | string |
| `Expr_v1_kind` | `r_expr_v1_kind` (scalar column) | string |
| `Expr_v2` | `r_expr_v2` | value → Expr_v2_value, kind → Expr_v2_kind |
| `Expr_v2_value` | `r_expr_v2_value` (scalar column) | boolean |
| `Expr_v2_kind` | `r_expr_v2_kind` (scalar column) | string |
| `Expr_v3` | `r_expr_v3` | expr → Expr, kind → Expr_v3_kind |
| `Expr_v3_kind` | `r_expr_v3_kind` (scalar column) | string |
| `Expr_v4` | `r_expr_v4` | exprs → Expr_v4_exprs, kind → Expr_v4_kind |
| `Expr_v4_exprs` | `r_expr_v4_exprs` | Expr |
| `Expr_v4_kind` | `r_expr_v4_kind` (scalar column) | string |
| `Expr_v5` | `r_expr_v5` | exprs → Expr_v5_exprs, kind → Expr_v5_kind |
| `Expr_v5_exprs` | `r_expr_v5_exprs` | Expr |
| `Expr_v5_kind` | `r_expr_v5_kind` (scalar column) | string |
| `Expr_v6` | `r_expr_v6` | subject → Operand, predicate → Expr_v6_predicate, roles → Expr_v6_roles, value → Expr_v6_value, polarity → Polarity, context → Expr_v6_context, kind → Expr_v6_kind |
| `Expr_v6_predicate` | `r_expr_v6_predicate` (scalar column) | string |
| `Expr_v6_roles` | `r_expr_v6_roles` | Expr_v6_roles_item |
| `Expr_v6_roles_item` | `r_expr_v6_roles_item` | 0 → Expr_v6_roles_item_p0, 1 → Operand |
| `Expr_v6_roles_item_p0` | `r_expr_v6_roles_item_p0` (scalar column) | string |
| `Expr_v6_value` | `r_expr_v6_value` | Operand, Expr_v6_value_v1 |
| `Expr_v6_value_v1` | `r_expr_v6_value_v1` (scalar column) | null |
| `Expr_v6_context` | `r_expr_v6_context` | Operand, Expr_v6_context_v1 |
| `Expr_v6_context_v1` | `r_expr_v6_context_v1` (scalar column) | null |
| `Expr_v6_kind` | `r_expr_v6_kind` (scalar column) | string |
| `Expr_v7` | `r_expr_v7` | subject → Operand, predicate → Expr_v7_predicate, roles → Expr_v7_roles, value → Expr_v7_value, context → Expr_v7_context, kind → Expr_v7_kind |
| `Expr_v7_predicate` | `r_expr_v7_predicate` (scalar column) | string |
| `Expr_v7_roles` | `r_expr_v7_roles` | Expr_v7_roles_item |
| `Expr_v7_roles_item` | `r_expr_v7_roles_item` | 0 → Expr_v7_roles_item_p0, 1 → Operand |
| `Expr_v7_roles_item_p0` | `r_expr_v7_roles_item_p0` (scalar column) | string |
| `Expr_v7_value` | `r_expr_v7_value` | Operand, Expr_v7_value_v1 |
| `Expr_v7_value_v1` | `r_expr_v7_value_v1` (scalar column) | null |
| `Expr_v7_context` | `r_expr_v7_context` | Operand, Expr_v7_context_v1 |
| `Expr_v7_context_v1` | `r_expr_v7_context_v1` (scalar column) | null |
| `Expr_v7_kind` | `r_expr_v7_kind` (scalar column) | string |
| `Expr_v8` | `r_expr_v8` | left → Operand, op → Comparator, right → Operand, kind → Expr_v8_kind |
| `Comparator` | `r_comparator` (scalar column) | string |
| `Expr_v8_kind` | `r_expr_v8_kind` (scalar column) | string |
| `Expr_v9` | `r_expr_v9` | left → Operand, relation → TemporalRelation, right → Operand, kind → Expr_v9_kind |
| `Expr_v9_kind` | `r_expr_v9_kind` (scalar column) | string |
| `Expr_v10` | `r_expr_v10` | element → Operand, collection → Operand, complete → Expr_v10_complete, kind → Expr_v10_kind |
| `Expr_v10_complete` | `r_expr_v10_complete` | Expr_v10_complete_v0, Expr_v10_complete_v1 |
| `Expr_v10_complete_v0` | `r_expr_v10_complete_v0` (scalar column) | boolean |
| `Expr_v10_complete_v1` | `r_expr_v10_complete_v1` (scalar column) | null |
| `Expr_v10_kind` | `r_expr_v10_kind` (scalar column) | string |
| `Expr_v11` | `r_expr_v11` | collection → Operand, op → Comparator, count → Value, complete → Expr_v11_complete, kind → Expr_v11_kind |
| `Expr_v11_complete` | `r_expr_v11_complete` | Expr_v11_complete_v0, Expr_v11_complete_v1 |
| `Expr_v11_complete_v0` | `r_expr_v11_complete_v0` (scalar column) | boolean |
| `Expr_v11_complete_v1` | `r_expr_v11_complete_v1` (scalar column) | null |
| `Expr_v11_kind` | `r_expr_v11_kind` (scalar column) | string |
| `Expr_v12` | `r_expr_v12` | subject → Operand, predicate → Expr_v12_predicate, roles → Expr_v12_roles, value → Expr_v12_value, context → Expr_v12_context, kind → Expr_v12_kind |
| `Expr_v12_predicate` | `r_expr_v12_predicate` (scalar column) | string |
| `Expr_v12_roles` | `r_expr_v12_roles` | Expr_v12_roles_item |
| `Expr_v12_roles_item` | `r_expr_v12_roles_item` | 0 → Expr_v12_roles_item_p0, 1 → Operand |
| `Expr_v12_roles_item_p0` | `r_expr_v12_roles_item_p0` (scalar column) | string |
| `Expr_v12_value` | `r_expr_v12_value` | Operand, Expr_v12_value_v1 |
| `Expr_v12_value_v1` | `r_expr_v12_value_v1` (scalar column) | null |
| `Expr_v12_context` | `r_expr_v12_context` | Operand, Expr_v12_context_v1 |
| `Expr_v12_context_v1` | `r_expr_v12_context_v1` (scalar column) | null |
| `Expr_v12_kind` | `r_expr_v12_kind` (scalar column) | string |
| `Expr_v13` | `r_expr_v13` | variable → Expr_v13_variable, over → Operand, complete → Expr_v13_complete, quantifier → Quantifier, body → Expr, kind → Expr_v13_kind |
| `Expr_v13_variable` | `r_expr_v13_variable` (scalar column) | string |
| `Expr_v13_complete` | `r_expr_v13_complete` (scalar column) | boolean |
| `Quantifier` | `r_quantifier` (scalar column) | string |
| `Expr_v13_kind` | `r_expr_v13_kind` (scalar column) | string |
| `Expr_v14` | `r_expr_v14` | subject → Operand, predicate → Expr_v14_predicate, role → Expr_v14_role, participant → Operand, kind → Expr_v14_kind |
| `Expr_v14_predicate` | `r_expr_v14_predicate` (scalar column) | string |
| `Expr_v14_role` | `r_expr_v14_role` (scalar column) | string |
| `Expr_v14_kind` | `r_expr_v14_kind` (scalar column) | string |
| `Payload_v21_record_kind` | `r_payload_v21_record_kind` (scalar column) | string |
| `Payload_v22` | `r_payload_v22` | namespace → Payload_v22_namespace, key → Payload_v22_key, labels → Payload_v22_labels, kind → RuleKind, commitPolicy → CommitPolicy, applicability → Applicability, subjectTypes → Payload_v22_subjectTypes, targetPredicates → Payload_v22_targetPredicates, expression → Expr, capabilities → Payload_v22_capabilities, executable → Payload_v22_executable, validity → Validity, record_kind → Payload_v22_record_kind |
| `Payload_v22_namespace` | `r_payload_v22_namespace` (scalar column) | string |
| `Payload_v22_key` | `r_payload_v22_key` (scalar column) | string |
| `Payload_v22_labels` | `r_payload_v22_labels` | Payload_v22_labels_item |
| `Payload_v22_labels_item` | `r_payload_v22_labels_item` (scalar column) | string |
| `RuleKind` | `r_rule_kind` | RuleKind_v0, RuleKind_v1, RuleKind_v2, RuleKind_v3, RuleKind_v4, RuleKind_v5, RuleKind_v6 |
| `RuleKind_v0` | `r_rule_kind_v0` (scalar column) | string |
| `RuleKind_v1` | `r_rule_kind_v1` (scalar column) | string |
| `RuleKind_v2` | `r_rule_kind_v2` (scalar column) | string |
| `RuleKind_v3` | `r_rule_kind_v3` (scalar column) | string |
| `RuleKind_v4` | `r_rule_kind_v4` (scalar column) | string |
| `RuleKind_v5` | `r_rule_kind_v5` (scalar column) | string |
| `RuleKind_v6` | `r_rule_kind_v6` (scalar column) | string |
| `CommitPolicy` | `r_commit_policy` | CommitPolicy_v0, CommitPolicy_v1, CommitPolicy_v2, CommitPolicy_v3, CommitPolicy_v4, CommitPolicy_v5 |
| `CommitPolicy_v0` | `r_commit_policy_v0` (scalar column) | string |
| `CommitPolicy_v1` | `r_commit_policy_v1` (scalar column) | string |
| `CommitPolicy_v2` | `r_commit_policy_v2` (scalar column) | string |
| `CommitPolicy_v3` | `r_commit_policy_v3` (scalar column) | string |
| `CommitPolicy_v4` | `r_commit_policy_v4` (scalar column) | string |
| `CommitPolicy_v5` | `r_commit_policy_v5` (scalar column) | string |
| `Payload_v22_subjectTypes` | `r_payload_v22_subject_types` | RecordId |
| `Payload_v22_targetPredicates` | `r_payload_v22_target_predicates` | Payload_v22_targetPredicates_item |
| `Payload_v22_targetPredicates_item` | `r_payload_v22_target_predicates_item` (scalar column) | string |
| `Payload_v22_capabilities` | `r_payload_v22_capabilities` | Payload_v22_capabilities_item |
| `Payload_v22_capabilities_item` | `r_payload_v22_capabilities_item` (scalar column) | string |
| `Payload_v22_executable` | `r_payload_v22_executable` (scalar column) | boolean |
| `Payload_v22_record_kind` | `r_payload_v22_record_kind` (scalar column) | string |
| `Payload_v23` | `r_payload_v23` | rule → RecordRef, ruleVersion → Payload_v23_ruleVersion, scope → Scope, validity → Validity, authorizingDecision → RecordRef, rationale → Payload_v23_rationale, record_kind → Payload_v23_record_kind |
| `Payload_v23_ruleVersion` | `r_payload_v23_rule_version` | RecordVersionId, Payload_v23_ruleVersion_v1 |
| `Payload_v23_ruleVersion_v1` | `r_payload_v23_rule_version_v1` (scalar column) | null |
| `Payload_v23_rationale` | `r_payload_v23_rationale` (scalar column) | string |
| `Payload_v23_record_kind` | `r_payload_v23_record_kind` (scalar column) | string |
| `Payload_v24` | `r_payload_v24` | occurrence → OccurrenceMode, action → Payload_v24_action, worlds → Payload_v24_worlds, region → Payload_v24_region, time → TemporalExpression, sequence → Payload_v24_sequence, occurrenceId → Payload_v24_occurrenceId, participants → Payload_v24_participants, preconditions → Payload_v24_preconditions, effects → Payload_v24_effects, labels → Payload_v24_labels, expansionVersion → Payload_v24_expansionVersion, record_kind → Payload_v24_record_kind |
| `OccurrenceMode` | `r_occurrence_mode` | OccurrenceMode_v0, OccurrenceMode_v1 |
| `OccurrenceMode_v0` | `r_occurrence_mode_v0` (scalar column) | string |
| `OccurrenceMode_v1` | `r_occurrence_mode_v1` | descriptive → OccurrenceMode_v1_descriptive |
| `OccurrenceMode_v1_descriptive` | `r_occurrence_mode_v1_descriptive` | label → OccurrenceMode_v1_descriptive_label |
| `OccurrenceMode_v1_descriptive_label` | `r_occurrence_mode_v1_descriptive_label` (scalar column) | string |
| `Payload_v24_action` | `r_payload_v24_action` | RecordRef, Payload_v24_action_v1 |
| `Payload_v24_action_v1` | `r_payload_v24_action_v1` (scalar column) | null |
| `Payload_v24_worlds` | `r_payload_v24_worlds` | WorldId |
| `Payload_v24_region` | `r_payload_v24_region` | RecordRef, Payload_v24_region_v1 |
| `Payload_v24_region_v1` | `r_payload_v24_region_v1` (scalar column) | null |
| `Payload_v24_sequence` | `r_payload_v24_sequence` | Payload_v24_sequence_v0, Payload_v24_sequence_v1 |
| `Payload_v24_sequence_v0` | `r_payload_v24_sequence_v0` (scalar column) | string |
| `Payload_v24_sequence_v1` | `r_payload_v24_sequence_v1` (scalar column) | null |
| `Payload_v24_occurrenceId` | `r_payload_v24_occurrence_id` | Payload_v24_occurrenceId_v0, Payload_v24_occurrenceId_v1 |
| `Payload_v24_occurrenceId_v0` | `r_payload_v24_occurrence_id_v0` (scalar column) | string |
| `Payload_v24_occurrenceId_v1` | `r_payload_v24_occurrence_id_v1` (scalar column) | null |
| `Payload_v24_participants` | `r_payload_v24_participants` | EventParticipant |
| `EventParticipant` | `r_event_participant` | record → RecordRef, role → EventParticipant_role |
| `EventParticipant_role` | `r_event_participant_role` (scalar column) | string |
| `Payload_v24_preconditions` | `r_payload_v24_preconditions` | Expr |
| `Payload_v24_effects` | `r_payload_v24_effects` | EntityEffect |
| `EntityEffect` | `r_entity_effect` | slot → EntityEffect_slot, proposition → RecordRef, polarity → Polarity, validity → Validity, scope → Scope, order → EntityEffect_order |
| `EntityEffect_slot` | `r_entity_effect_slot` (scalar column) | string |
| `EntityEffect_order` | `r_entity_effect_order` (scalar column) | integer |
| `Payload_v24_labels` | `r_payload_v24_labels` | Payload_v24_labels_item |
| `Payload_v24_labels_item` | `r_payload_v24_labels_item` (scalar column) | string |
| `Payload_v24_expansionVersion` | `r_payload_v24_expansion_version` | Payload_v24_expansionVersion_v0, Payload_v24_expansionVersion_v1 |
| `Payload_v24_expansionVersion_v0` | `r_payload_v24_expansion_version_v0` (scalar column) | string |
| `Payload_v24_expansionVersion_v1` | `r_payload_v24_expansion_version_v1` (scalar column) | null |
| `Payload_v24_record_kind` | `r_payload_v24_record_kind` (scalar column) | string |
| `Payload_v25` | `r_payload_v25` | item → RecordRef, holderPredicate → RecordRef, powerPredicate → RecordRef, value → Value, scope → Scope, validity → Validity, record_kind → Payload_v25_record_kind |
| `Payload_v25_record_kind` | `r_payload_v25_record_kind` (scalar column) | string |
| `Payload_v26` | `r_payload_v26` | namespace → Payload_v26_namespace, key → Payload_v26_key, labels → Payload_v26_labels, requirements → Payload_v26_requirements, consequenceContract → ConsequenceContract, scope → Scope, validity → Validity, record_kind → Payload_v26_record_kind |
| `Payload_v26_namespace` | `r_payload_v26_namespace` (scalar column) | string |
| `Payload_v26_key` | `r_payload_v26_key` (scalar column) | string |
| `Payload_v26_labels` | `r_payload_v26_labels` | Payload_v26_labels_item |
| `Payload_v26_labels_item` | `r_payload_v26_labels_item` (scalar column) | string |
| `Payload_v26_requirements` | `r_payload_v26_requirements` | AttributeRequirement |
| `AttributeRequirement` | `r_attribute_requirement` | role → AttributeRequirement_role, predicate → RecordRef, value → Value |
| `AttributeRequirement_role` | `r_attribute_requirement_role` (scalar column) | string |
| `ConsequenceContract` | `r_consequence_contract` | kind → ConsequenceKind, slots → ConsequenceContract_slots |
| `ConsequenceKind` | `r_consequence_kind` (scalar column) | string |
| `ConsequenceContract_slots` | `r_consequence_contract_slots` | EffectSlot |
| `EffectSlot` | `r_effect_slot` | slot → EffectSlot_slot, order → EffectSlot_order, presence → EffectPresence, target → EffectTarget, condition → EffectCondition, change → EffectChange, lifetime → EffectLifetime |
| `EffectSlot_slot` | `r_effect_slot_slot` (scalar column) | string |
| `EffectSlot_order` | `r_effect_slot_order` (scalar column) | integer |
| `EffectPresence` | `r_effect_presence` (scalar column) | string |
| `EffectTarget` | `r_effect_target` | role → EffectTarget_role, predicate → RecordRef |
| `EffectTarget_role` | `r_effect_target_role` (scalar column) | string |
| `EffectCondition` | `r_effect_condition` | EffectCondition_v0, EffectCondition_v1 |
| `EffectCondition_v0` | `r_effect_condition_v0` | kind → EffectCondition_v0_kind |
| `EffectCondition_v0_kind` | `r_effect_condition_v0_kind` (scalar column) | string |
| `EffectCondition_v1` | `r_effect_condition_v1` | role → EffectCondition_v1_role, predicate → RecordRef, value → Value, kind → EffectCondition_v1_kind |
| `EffectCondition_v1_role` | `r_effect_condition_v1_role` (scalar column) | string |
| `EffectCondition_v1_kind` | `r_effect_condition_v1_kind` (scalar column) | string |
| `EffectChange` | `r_effect_change` | EffectChange_v0, EffectChange_v1 |
| `EffectChange_v0` | `r_effect_change_v0` | polarity → Polarity, value → Value, kind → EffectChange_v0_kind |
| `EffectChange_v0_kind` | `r_effect_change_v0_kind` (scalar column) | string |
| `EffectChange_v1` | `r_effect_change_v1` | delta → ConsequenceInteger, minimum → ConsequenceInteger, maximum → ConsequenceInteger, unit → EffectChange_v1_unit, kind → EffectChange_v1_kind |
| `ConsequenceInteger` | `r_consequence_integer` (scalar column) | string |
| `EffectChange_v1_unit` | `r_effect_change_v1_unit` | UnitId, EffectChange_v1_unit_v1 |
| `EffectChange_v1_unit_v1` | `r_effect_change_v1_unit_v1` (scalar column) | null |
| `EffectChange_v1_kind` | `r_effect_change_v1_kind` (scalar column) | string |
| `EffectLifetime` | `r_effect_lifetime` | EffectLifetime_v0, EffectLifetime_v1 |
| `EffectLifetime_v0` | `r_effect_lifetime_v0` | kind → EffectLifetime_v0_kind |
| `EffectLifetime_v0_kind` | `r_effect_lifetime_v0_kind` (scalar column) | string |
| `EffectLifetime_v1` | `r_effect_lifetime_v1` | count → ConsequenceInteger, kind → EffectLifetime_v1_kind |
| `EffectLifetime_v1_kind` | `r_effect_lifetime_v1_kind` (scalar column) | string |
| `Payload_v26_record_kind` | `r_payload_v26_record_kind` (scalar column) | string |
| `Payload_v27` | `r_payload_v27` | holder → RecordRef, proposition → RecordRef, attitude → EpistemicAttitudeKind, certainty → Payload_v27_certainty, validity → Validity, basis → EvidenceBasis, record_kind → Payload_v27_record_kind |
| `Payload_v27_certainty` | `r_payload_v27_certainty` | Payload_v27_certainty_v0, Payload_v27_certainty_v1 |
| `Payload_v27_certainty_v0` | `r_payload_v27_certainty_v0` (scalar column) | string |
| `Payload_v27_certainty_v1` | `r_payload_v27_certainty_v1` (scalar column) | null |
| `Payload_v27_record_kind` | `r_payload_v27_record_kind` (scalar column) | string |
| `Payload_v28` | `r_payload_v28` | observer → RecordRef, observed → RecordRef, sensoryAccess → Payload_v28_sensoryAccess, time → TemporalExpression, interpretation → Payload_v28_interpretation, basis → EvidenceBasis, record_kind → Payload_v28_record_kind |
| `Payload_v28_sensoryAccess` | `r_payload_v28_sensory_access` (scalar column) | boolean |
| `Payload_v28_interpretation` | `r_payload_v28_interpretation` | RecordRef, Payload_v28_interpretation_v1 |
| `Payload_v28_interpretation_v1` | `r_payload_v28_interpretation_v1` (scalar column) | null |
| `Payload_v28_record_kind` | `r_payload_v28_record_kind` (scalar column) | string |
| `Payload_v29` | `r_payload_v29` | sender → RecordRef, intendedRecipients → Payload_v29_intendedRecipients, actualRecipients → Payload_v29_actualRecipients, content → Payload_v29_content, channel → Payload_v29_channel, sentAt → TemporalExpression, receivedAt → Payload_v29_receivedAt, distorted → Payload_v29_distorted, record_kind → Payload_v29_record_kind |
| `Payload_v29_intendedRecipients` | `r_payload_v29_intended_recipients` | RecordRef |
| `Payload_v29_actualRecipients` | `r_payload_v29_actual_recipients` | RecordRef |
| `Payload_v29_content` | `r_payload_v29_content` | RecordRef |
| `Payload_v29_channel` | `r_payload_v29_channel` | Payload_v29_channel_v0, Payload_v29_channel_v1 |
| `Payload_v29_channel_v0` | `r_payload_v29_channel_v0` (scalar column) | string |
| `Payload_v29_channel_v1` | `r_payload_v29_channel_v1` (scalar column) | null |
| `Payload_v29_receivedAt` | `r_payload_v29_received_at` | TemporalExpression, Payload_v29_receivedAt_v1 |
| `Payload_v29_receivedAt_v1` | `r_payload_v29_received_at_v1` (scalar column) | null |
| `Payload_v29_distorted` | `r_payload_v29_distorted` (scalar column) | boolean |
| `Payload_v29_record_kind` | `r_payload_v29_record_kind` (scalar column) | string |
| `Payload_v30` | `r_payload_v30` | holder → RecordRef, content → RecordRef, alleged → Payload_v30_alleged, accessibility → Payload_v30_accessibility, altered → Payload_v30_altered, validity → Validity, record_kind → Payload_v30_record_kind |
| `Payload_v30_alleged` | `r_payload_v30_alleged` | RecordRef, Payload_v30_alleged_v1 |
| `Payload_v30_alleged_v1` | `r_payload_v30_alleged_v1` (scalar column) | null |
| `Payload_v30_accessibility` | `r_payload_v30_accessibility` (scalar column) | string |
| `Payload_v30_altered` | `r_payload_v30_altered` (scalar column) | boolean |
| `Payload_v30_record_kind` | `r_payload_v30_record_kind` (scalar column) | string |
| `Payload_v31` | `r_payload_v31` | scope → Payload_v31_scope, fictionalKnowers → Payload_v31_fictionalKnowers, readerDisclosed → Payload_v31_readerDisclosed, concealment → Payload_v31_concealment, validity → Validity, record_kind → Payload_v31_record_kind |
| `Payload_v31_scope` | `r_payload_v31_scope` | RecordRef |
| `Payload_v31_fictionalKnowers` | `r_payload_v31_fictional_knowers` | RecordRef |
| `Payload_v31_readerDisclosed` | `r_payload_v31_reader_disclosed` (scalar column) | boolean |
| `Payload_v31_concealment` | `r_payload_v31_concealment` | Payload_v31_concealment_v0, Payload_v31_concealment_v1 |
| `Payload_v31_concealment_v0` | `r_payload_v31_concealment_v0` (scalar column) | string |
| `Payload_v31_concealment_v1` | `r_payload_v31_concealment_v1` (scalar column) | null |
| `Payload_v31_record_kind` | `r_payload_v31_record_kind` (scalar column) | string |
| `Payload_v32` | `r_payload_v32` | actor → RecordRef, desired → Payload_v32_desired, prerequisites → Payload_v32_prerequisites, steps → Payload_v32_steps, status → PlanStatus, validity → Validity, record_kind → Payload_v32_record_kind |
| `Payload_v32_desired` | `r_payload_v32_desired` | RecordRef, Payload_v32_desired_v1 |
| `Payload_v32_desired_v1` | `r_payload_v32_desired_v1` (scalar column) | null |
| `Payload_v32_prerequisites` | `r_payload_v32_prerequisites` | Expr |
| `Payload_v32_steps` | `r_payload_v32_steps` | RecordRef |
| `PlanStatus` | `r_plan_status` (scalar column) | string |
| `Payload_v32_record_kind` | `r_payload_v32_record_kind` (scalar column) | string |
| `Payload_v33` | `r_payload_v33` | parties → Payload_v33_parties, obligated → RecordRef, conditions → Payload_v33_conditions, deadline → Payload_v33_deadline, status → CommitmentStatus, record_kind → Payload_v33_record_kind |
| `Payload_v33_parties` | `r_payload_v33_parties` | CommitmentParty |
| `CommitmentParty` | `r_commitment_party` | record → RecordRef, role → CommitmentParty_role |
| `CommitmentParty_role` | `r_commitment_party_role` (scalar column) | string |
| `Payload_v33_conditions` | `r_payload_v33_conditions` | Expr |
| `Payload_v33_deadline` | `r_payload_v33_deadline` | TemporalExpression, Payload_v33_deadline_v1 |
| `Payload_v33_deadline_v1` | `r_payload_v33_deadline_v1` (scalar column) | null |
| `CommitmentStatus` | `r_commitment_status` (scalar column) | string |
| `Payload_v33_record_kind` | `r_payload_v33_record_kind` (scalar column) | string |
| `Payload_v34` | `r_payload_v34` | label → Payload_v34_label, externalId → Payload_v34_externalId, origin → OriginMetadata, versions → Payload_v34_versions, record_kind → Payload_v34_record_kind |
| `Payload_v34_label` | `r_payload_v34_label` (scalar column) | string |
| `Payload_v34_externalId` | `r_payload_v34_external_id` | Payload_v34_externalId_v0, Payload_v34_externalId_v1 |
| `Payload_v34_externalId_v0` | `r_payload_v34_external_id_v0` (scalar column) | string |
| `Payload_v34_externalId_v1` | `r_payload_v34_external_id_v1` (scalar column) | null |
| `OriginMetadata` | `r_origin_metadata` | externallyAssertedAuthor → OriginMetadata_externallyAssertedAuthor, originNote → OriginMetadata_originNote |
| `OriginMetadata_externallyAssertedAuthor` | `r_origin_metadata_externally_asserted_author` | OriginMetadata_externallyAssertedAuthor_v0, OriginMetadata_externallyAssertedAuthor_v1 |
| `OriginMetadata_externallyAssertedAuthor_v0` | `r_origin_metadata_externally_asserted_author_v0` (scalar column) | string |
| `OriginMetadata_externallyAssertedAuthor_v1` | `r_origin_metadata_externally_asserted_author_v1` (scalar column) | null |
| `OriginMetadata_originNote` | `r_origin_metadata_origin_note` | OriginMetadata_originNote_v0, OriginMetadata_originNote_v1 |
| `OriginMetadata_originNote_v0` | `r_origin_metadata_origin_note_v0` (scalar column) | string |
| `OriginMetadata_originNote_v1` | `r_origin_metadata_origin_note_v1` (scalar column) | null |
| `Payload_v34_versions` | `r_payload_v34_versions` | RecordId |
| `Payload_v34_record_kind` | `r_payload_v34_record_kind` (scalar column) | string |
| `Payload_v35` | `r_payload_v35` | source → RecordRef, digest → Payload_v35_digest, mediaType → Payload_v35_mediaType, byteSize → Payload_v35_byteSize, importActor → PrincipalId, importTime → Payload_v35_importTime, decoding → DecodingDescriptor, origin → OriginMetadata, record_kind → Payload_v35_record_kind |
| `Payload_v35_digest` | `r_payload_v35_digest` (scalar column) | string |
| `Payload_v35_mediaType` | `r_payload_v35_media_type` (scalar column) | string |
| `Payload_v35_byteSize` | `r_payload_v35_byte_size` (scalar column) | integer |
| `PrincipalId` | `r_principal_id` (scalar column) | string |
| `Payload_v35_importTime` | `r_payload_v35_import_time` (scalar column) | string |
| `DecodingDescriptor` | `r_decoding_descriptor` | encoding → DecodingDescriptor_encoding, representation → DecodingDescriptor_representation, byteLength → DecodingDescriptor_byteLength |
| `DecodingDescriptor_encoding` | `r_decoding_descriptor_encoding` (scalar column) | string |
| `DecodingDescriptor_representation` | `r_decoding_descriptor_representation` (scalar column) | string |
| `DecodingDescriptor_byteLength` | `r_decoding_descriptor_byte_length` (scalar column) | integer |
| `Payload_v35_record_kind` | `r_payload_v35_record_kind` (scalar column) | string |
| `Payload_v36` | `r_payload_v36` | sourceVersion → VersionRef, locator → AnchorLocator, excerptDigest → Payload_v36_excerptDigest, excerpt → Payload_v36_excerpt, context → Payload_v36_context, record_kind → Payload_v36_record_kind |
| `AnchorLocator` | `r_anchor_locator` | AnchorLocator_v0, AnchorLocator_v1 |
| `AnchorLocator_v0` | `r_anchor_locator_v0` | start → AnchorLocator_v0_start, end → AnchorLocator_v0_end, kind → AnchorLocator_v0_kind |
| `AnchorLocator_v0_start` | `r_anchor_locator_v0_start` (scalar column) | integer |
| `AnchorLocator_v0_end` | `r_anchor_locator_v0_end` (scalar column) | integer |
| `AnchorLocator_v0_kind` | `r_anchor_locator_v0_kind` (scalar column) | string |
| `AnchorLocator_v1` | `r_anchor_locator_v1` | path → AnchorLocator_v1_path, kind → AnchorLocator_v1_kind |
| `AnchorLocator_v1_path` | `r_anchor_locator_v1_path` | AnchorLocator_v1_path_item |
| `AnchorLocator_v1_path_item` | `r_anchor_locator_v1_path_item` (scalar column) | string |
| `AnchorLocator_v1_kind` | `r_anchor_locator_v1_kind` (scalar column) | string |
| `Payload_v36_excerptDigest` | `r_payload_v36_excerpt_digest` (scalar column) | string |
| `Payload_v36_excerpt` | `r_payload_v36_excerpt` (scalar column) | string |
| `Payload_v36_context` | `r_payload_v36_context` | RecordRef, Payload_v36_context_v1 |
| `Payload_v36_context_v1` | `r_payload_v36_context_v1` (scalar column) | null |
| `Payload_v36_record_kind` | `r_payload_v36_record_kind` (scalar column) | string |
| `Payload_v37` | `r_payload_v37` | fingerprints → Payload_v37_fingerprints, mode → IssueDecisionMode, scope → Payload_v37_scope, rationale → Payload_v37_rationale, principal → PrincipalId, record_kind → Payload_v37_record_kind |
| `Payload_v37_fingerprints` | `r_payload_v37_fingerprints` | FindingFingerprint |
| `FindingFingerprint` | `r_finding_fingerprint` (scalar column) | string |
| `IssueDecisionMode` | `r_issue_decision_mode` | IssueDecisionMode_v0, IssueDecisionMode_v1, IssueDecisionMode_v2 |
| `IssueDecisionMode_v0` | `r_issue_decision_mode_v0` (scalar column) | string |
| `IssueDecisionMode_v1` | `r_issue_decision_mode_v1` (scalar column) | string |
| `IssueDecisionMode_v2` | `r_issue_decision_mode_v2` (scalar column) | string |
| `Payload_v37_scope` | `r_payload_v37_scope` (scalar column) | string |
| `Payload_v37_rationale` | `r_payload_v37_rationale` (scalar column) | string |
| `Payload_v37_record_kind` | `r_payload_v37_record_kind` (scalar column) | string |
| `DomainOperation` | `r_domain_operation` | DomainOperation_v0, DomainOperation_v1, DomainOperation_v2, DomainOperation_v3, DomainOperation_v4, DomainOperation_v5, DomainOperation_v6, DomainOperation_v7, DomainOperation_v8, DomainOperation_v9, DomainOperation_v10, DomainOperation_v11, DomainOperation_v12, DomainOperation_v13, DomainOperation_v14, DomainOperation_v15, DomainOperation_v16, DomainOperation_v17, DomainOperation_v18, DomainOperation_v19, DomainOperation_v20, DomainOperation_v21, DomainOperation_v22, DomainOperation_v23, DomainOperation_v24, DomainOperation_v25, DomainOperation_v26, DomainOperation_v27, DomainOperation_v28, DomainOperation_v29, DomainOperation_v30, DomainOperation_v31, DomainOperation_v32, DomainOperation_v33, DomainOperation_v34, DomainOperation_v35, DomainOperation_v36, DomainOperation_v37, DomainOperation_v38, DomainOperation_v39, DomainOperation_v40, DomainOperation_v41, DomainOperation_v42, DomainOperation_v43, DomainOperation_v44, DomainOperation_v45, DomainOperation_v46, DomainOperation_v47, DomainOperation_v48, DomainOperation_v49 |
| `DomainOperation_v0` | `r_domain_operation_v0` | client_ref → DomainOperation_v0_client_ref, record → Appearance, kind → DomainOperation_v0_kind |
| `DomainOperation_v0_client_ref` | `r_domain_operation_v0_client_ref` (scalar column) | string |
| `Appearance` | `r_appearance` | target → AppearanceTarget, label → Appearance_label, physical_description → Appearance_physical_description, atmosphere → Appearance_atmosphere, images → Appearance_images, links → Appearance_links, validity → Validity |
| `Appearance_label` | `r_appearance_label` (scalar column) | string |
| `Appearance_physical_description` | `r_appearance_physical_description` (scalar column) | string |
| `Appearance_atmosphere` | `r_appearance_atmosphere` (scalar column) | string |
| `Appearance_images` | `r_appearance_images` | AppearanceImage |
| `Appearance_links` | `r_appearance_links` | AppearanceLink |
| `DomainOperation_v0_kind` | `r_domain_operation_v0_kind` (scalar column) | string |
| `DomainOperation_v1` | `r_domain_operation_v1` | record → RecordRef, expected_version → RecordVersionId, replacement → Appearance, kind → DomainOperation_v1_kind |
| `DomainOperation_v1_kind` | `r_domain_operation_v1_kind` (scalar column) | string |
| `DomainOperation_v2` | `r_domain_operation_v2` | client_ref → DomainOperation_v2_client_ref, record → ImageAsset, kind → DomainOperation_v2_kind |
| `DomainOperation_v2_client_ref` | `r_domain_operation_v2_client_ref` (scalar column) | string |
| `ImageAsset` | `r_image_asset` | digest → ImageAsset_digest, media_type → ImageAsset_media_type, byte_size → ImageAsset_byte_size, width → ImageAsset_width, height → ImageAsset_height, original_name → ImageAsset_original_name |
| `ImageAsset_digest` | `r_image_asset_digest` (scalar column) | string |
| `ImageAsset_media_type` | `r_image_asset_media_type` (scalar column) | string |
| `ImageAsset_byte_size` | `r_image_asset_byte_size` (scalar column) | integer |
| `ImageAsset_width` | `r_image_asset_width` (scalar column) | integer |
| `ImageAsset_height` | `r_image_asset_height` (scalar column) | integer |
| `ImageAsset_original_name` | `r_image_asset_original_name` (scalar column) | string |
| `DomainOperation_v2_kind` | `r_domain_operation_v2_kind` (scalar column) | string |
| `DomainOperation_v3` | `r_domain_operation_v3` | record → RecordRef, expected_version → RecordVersionId, value → DomainOperation_v3_value, mode → TimeChangeKind, reason → DomainOperation_v3_reason, kind → DomainOperation_v3_kind |
| `DomainOperation_v3_value` | `r_domain_operation_v3_value` (scalar column) | string |
| `TimeChangeKind` | `r_time_change_kind` (scalar column) | string |
| `DomainOperation_v3_reason` | `r_domain_operation_v3_reason` (scalar column) | string |
| `DomainOperation_v3_kind` | `r_domain_operation_v3_kind` (scalar column) | string |
| `DomainOperation_v4` | `r_domain_operation_v4` | client_ref → DomainOperation_v4_client_ref, record → Entity, kind → DomainOperation_v4_kind |
| `DomainOperation_v4_client_ref` | `r_domain_operation_v4_client_ref` (scalar column) | string |
| `Entity` | `r_entity` | names → Entity_names, types → Entity_types, worldAssociations → Entity_worldAssociations, labels → Entity_labels, metadata → Entity_metadata |
| `Entity_names` | `r_entity_names` | ContextualName |
| `Entity_types` | `r_entity_types` | RecordId |
| `Entity_worldAssociations` | `r_entity_world_associations` | WorldAssociation |
| `Entity_labels` | `r_entity_labels` | Entity_labels_item |
| `Entity_labels_item` | `r_entity_labels_item` (scalar column) | string |
| `Entity_metadata` | `r_entity_metadata` | Value |
| `DomainOperation_v4_kind` | `r_domain_operation_v4_kind` (scalar column) | string |
| `DomainOperation_v5` | `r_domain_operation_v5` | record → RecordRef, expected_version → RecordVersionId, name → ContextualName, kind → DomainOperation_v5_kind |
| `DomainOperation_v5_kind` | `r_domain_operation_v5_kind` (scalar column) | string |
| `DomainOperation_v6` | `r_domain_operation_v6` | record → RecordRef, expected_version → RecordVersionId, entity_type → RecordId, kind → DomainOperation_v6_kind |
| `DomainOperation_v6_kind` | `r_domain_operation_v6_kind` (scalar column) | string |
| `DomainOperation_v7` | `r_domain_operation_v7` | client_ref → DomainOperation_v7_client_ref, record → World, kind → DomainOperation_v7_kind |
| `DomainOperation_v7_client_ref` | `r_domain_operation_v7_client_ref` (scalar column) | string |
| `World` | `r_world` | selector → World_selector, aliases → World_aliases, settingType → World_settingType, labels → World_labels, metadata → World_metadata |
| `World_selector` | `r_world_selector` (scalar column) | string |
| `World_aliases` | `r_world_aliases` | World_aliases_item |
| `World_aliases_item` | `r_world_aliases_item` (scalar column) | string |
| `World_settingType` | `r_world_setting_type` | World_settingType_v0, World_settingType_v1 |
| `World_settingType_v0` | `r_world_setting_type_v0` (scalar column) | string |
| `World_settingType_v1` | `r_world_setting_type_v1` (scalar column) | null |
| `World_labels` | `r_world_labels` | World_labels_item |
| `World_labels_item` | `r_world_labels_item` (scalar column) | string |
| `World_metadata` | `r_world_metadata` | Value |
| `DomainOperation_v7_kind` | `r_domain_operation_v7_kind` (scalar column) | string |
| `DomainOperation_v8` | `r_domain_operation_v8` | record → RecordRef, expected_version → RecordVersionId, new_selector → DomainOperation_v8_new_selector, kind → DomainOperation_v8_kind |
| `DomainOperation_v8_new_selector` | `r_domain_operation_v8_new_selector` (scalar column) | string |
| `DomainOperation_v8_kind` | `r_domain_operation_v8_kind` (scalar column) | string |
| `DomainOperation_v9` | `r_domain_operation_v9` | record → RecordRef, expected_version → RecordVersionId, alias → DomainOperation_v9_alias, kind → DomainOperation_v9_kind |
| `DomainOperation_v9_alias` | `r_domain_operation_v9_alias` (scalar column) | string |
| `DomainOperation_v9_kind` | `r_domain_operation_v9_kind` (scalar column) | string |
| `DomainOperation_v10` | `r_domain_operation_v10` | client_ref → DomainOperation_v10_client_ref, record → Work, kind → DomainOperation_v10_kind |
| `DomainOperation_v10_client_ref` | `r_domain_operation_v10_client_ref` (scalar column) | string |
| `Work` | `r_work` | kind → WorkKind, title → Work_title, labels → Work_labels, sourceRefs → Work_sourceRefs, versions → Work_versions, worldAssociations → Work_worldAssociations |
| `Work_title` | `r_work_title` (scalar column) | string |
| `Work_labels` | `r_work_labels` | Work_labels_item |
| `Work_labels_item` | `r_work_labels_item` (scalar column) | string |
| `Work_sourceRefs` | `r_work_source_refs` | RecordRef |
| `Work_versions` | `r_work_versions` | RecordId |
| `Work_worldAssociations` | `r_work_world_associations` | WorldAssociation |
| `DomainOperation_v10_kind` | `r_domain_operation_v10_kind` (scalar column) | string |
| `DomainOperation_v11` | `r_domain_operation_v11` | client_ref → DomainOperation_v11_client_ref, record → Saga, kind → DomainOperation_v11_kind |
| `DomainOperation_v11_client_ref` | `r_domain_operation_v11_client_ref` (scalar column) | string |
| `Saga` | `r_saga` | title → Saga_title, labels → Saga_labels, memberships → Saga_memberships |
| `Saga_title` | `r_saga_title` (scalar column) | string |
| `Saga_labels` | `r_saga_labels` | Saga_labels_item |
| `Saga_labels_item` | `r_saga_labels_item` (scalar column) | string |
| `Saga_memberships` | `r_saga_memberships` | SagaMembership |
| `DomainOperation_v11_kind` | `r_domain_operation_v11_kind` (scalar column) | string |
| `DomainOperation_v12` | `r_domain_operation_v12` | record → RecordRef, expected_version → RecordVersionId, binding → WorkBinding, kind → DomainOperation_v12_kind |
| `DomainOperation_v12_kind` | `r_domain_operation_v12_kind` (scalar column) | string |
| `DomainOperation_v13` | `r_domain_operation_v13` | record → RecordRef, expected_version → RecordVersionId, association → WorldAssociation, kind → DomainOperation_v13_kind |
| `DomainOperation_v13_kind` | `r_domain_operation_v13_kind` (scalar column) | string |
| `DomainOperation_v14` | `r_domain_operation_v14` | record → RecordRef, expected_version → RecordVersionId, membership → SagaMembership, kind → DomainOperation_v14_kind |
| `DomainOperation_v14_kind` | `r_domain_operation_v14_kind` (scalar column) | string |
| `DomainOperation_v15` | `r_domain_operation_v15` | client_ref → DomainOperation_v15_client_ref, proposition → Proposition, assertion → Assertion, kind → DomainOperation_v15_kind |
| `DomainOperation_v15_client_ref` | `r_domain_operation_v15_client_ref` (scalar column) | string |
| `Proposition` | `r_proposition` | predicate → RecordRef, subject → RecordRef, roles → Proposition_roles, value → Proposition_value, quantification → Quantification, context → RecordRef |
| `Proposition_roles` | `r_proposition_roles` | PropositionRole |
| `Proposition_value` | `r_proposition_value` | Value, Proposition_value_v1 |
| `Proposition_value_v1` | `r_proposition_value_v1` (scalar column) | null |
| `Assertion` | `r_assertion` | proposition → RecordRef, polarity → Polarity, scope → Scope, validity → Validity, persistence → PersistenceSemantics, precision → Precision, alternatives → Assertion_alternatives, basis → EvidenceBasis, establishedBy → Assertion_establishedBy |
| `Assertion_alternatives` | `r_assertion_alternatives` | Value |
| `Assertion_establishedBy` | `r_assertion_established_by` | EventEffectRef, Assertion_establishedBy_v1 |
| `Assertion_establishedBy_v1` | `r_assertion_established_by_v1` (scalar column) | null |
| `DomainOperation_v15_kind` | `r_domain_operation_v15_kind` (scalar column) | string |
| `DomainOperation_v16` | `r_domain_operation_v16` | client_ref → DomainOperation_v16_client_ref, proposition → Proposition, assertion → Assertion, kind → DomainOperation_v16_kind |
| `DomainOperation_v16_client_ref` | `r_domain_operation_v16_client_ref` (scalar column) | string |
| `DomainOperation_v16_kind` | `r_domain_operation_v16_kind` (scalar column) | string |
| `DomainOperation_v17` | `r_domain_operation_v17` | record → RecordRef, expected_version → RecordVersionId, at → TemporalExpression, basis → EvidenceBasis, kind → DomainOperation_v17_kind |
| `DomainOperation_v17_kind` | `r_domain_operation_v17_kind` (scalar column) | string |
| `DomainOperation_v18` | `r_domain_operation_v18` | record → RecordRef, expected_version → RecordVersionId, replacement → Assertion, rationale → DomainOperation_v18_rationale, kind → DomainOperation_v18_kind |
| `DomainOperation_v18_rationale` | `r_domain_operation_v18_rationale` (scalar column) | string |
| `DomainOperation_v18_kind` | `r_domain_operation_v18_kind` (scalar column) | string |
| `DomainOperation_v19` | `r_domain_operation_v19` | record → RecordRef, expected_version → RecordVersionId, rationale → DomainOperation_v19_rationale, kind → DomainOperation_v19_kind |
| `DomainOperation_v19_rationale` | `r_domain_operation_v19_rationale` (scalar column) | string |
| `DomainOperation_v19_kind` | `r_domain_operation_v19_kind` (scalar column) | string |
| `DomainOperation_v20` | `r_domain_operation_v20` | client_ref → DomainOperation_v20_client_ref, record → Proposition, kind → DomainOperation_v20_kind |
| `DomainOperation_v20_client_ref` | `r_domain_operation_v20_client_ref` (scalar column) | string |
| `DomainOperation_v20_kind` | `r_domain_operation_v20_kind` (scalar column) | string |
| `DomainOperation_v21` | `r_domain_operation_v21` | client_ref → DomainOperation_v21_client_ref, record → ItemPower, kind → DomainOperation_v21_kind |
| `DomainOperation_v21_client_ref` | `r_domain_operation_v21_client_ref` (scalar column) | string |
| `ItemPower` | `r_item_power` | item → RecordRef, holderPredicate → RecordRef, powerPredicate → RecordRef, value → Value, scope → Scope, validity → Validity |
| `DomainOperation_v21_kind` | `r_domain_operation_v21_kind` (scalar column) | string |
| `DomainOperation_v22` | `r_domain_operation_v22` | client_ref → DomainOperation_v22_client_ref, record → ActionDefinition, kind → DomainOperation_v22_kind |
| `DomainOperation_v22_client_ref` | `r_domain_operation_v22_client_ref` (scalar column) | string |
| `ActionDefinition` | `r_action_definition` | namespace → ActionDefinition_namespace, key → ActionDefinition_key, labels → ActionDefinition_labels, requirements → ActionDefinition_requirements, consequenceContract → ConsequenceContract, scope → Scope, validity → Validity |
| `ActionDefinition_namespace` | `r_action_definition_namespace` (scalar column) | string |
| `ActionDefinition_key` | `r_action_definition_key` (scalar column) | string |
| `ActionDefinition_labels` | `r_action_definition_labels` | ActionDefinition_labels_item |
| `ActionDefinition_labels_item` | `r_action_definition_labels_item` (scalar column) | string |
| `ActionDefinition_requirements` | `r_action_definition_requirements` | AttributeRequirement |
| `DomainOperation_v22_kind` | `r_domain_operation_v22_kind` (scalar column) | string |
| `DomainOperation_v23` | `r_domain_operation_v23` | client_ref → DomainOperation_v23_client_ref, record → Event, kind → DomainOperation_v23_kind |
| `DomainOperation_v23_client_ref` | `r_domain_operation_v23_client_ref` (scalar column) | string |
| `Event` | `r_event` | occurrence → OccurrenceMode, action → Event_action, worlds → Event_worlds, region → Event_region, time → TemporalExpression, sequence → Event_sequence, occurrenceId → Event_occurrenceId, participants → Event_participants, preconditions → Event_preconditions, effects → Event_effects, labels → Event_labels, expansionVersion → Event_expansionVersion |
| `Event_action` | `r_event_action` | RecordRef, Event_action_v1 |
| `Event_action_v1` | `r_event_action_v1` (scalar column) | null |
| `Event_worlds` | `r_event_worlds` | WorldId |
| `Event_region` | `r_event_region` | RecordRef, Event_region_v1 |
| `Event_region_v1` | `r_event_region_v1` (scalar column) | null |
| `Event_sequence` | `r_event_sequence` | Event_sequence_v0, Event_sequence_v1 |
| `Event_sequence_v0` | `r_event_sequence_v0` (scalar column) | string |
| `Event_sequence_v1` | `r_event_sequence_v1` (scalar column) | null |
| `Event_occurrenceId` | `r_event_occurrence_id` | Event_occurrenceId_v0, Event_occurrenceId_v1 |
| `Event_occurrenceId_v0` | `r_event_occurrence_id_v0` (scalar column) | string |
| `Event_occurrenceId_v1` | `r_event_occurrence_id_v1` (scalar column) | null |
| `Event_participants` | `r_event_participants` | EventParticipant |
| `Event_preconditions` | `r_event_preconditions` | Expr |
| `Event_effects` | `r_event_effects` | EntityEffect |
| `Event_labels` | `r_event_labels` | Event_labels_item |
| `Event_labels_item` | `r_event_labels_item` (scalar column) | string |
| `Event_expansionVersion` | `r_event_expansion_version` | Event_expansionVersion_v0, Event_expansionVersion_v1 |
| `Event_expansionVersion_v0` | `r_event_expansion_version_v0` (scalar column) | string |
| `Event_expansionVersion_v1` | `r_event_expansion_version_v1` (scalar column) | null |
| `DomainOperation_v23_kind` | `r_domain_operation_v23_kind` (scalar column) | string |
| `DomainOperation_v24` | `r_domain_operation_v24` | record → RecordRef, expected_version → RecordVersionId, replacement → Event, kind → DomainOperation_v24_kind |
| `DomainOperation_v24_kind` | `r_domain_operation_v24_kind` (scalar column) | string |
| `DomainOperation_v25` | `r_domain_operation_v25` | client_ref → DomainOperation_v25_client_ref, record → EpistemicAttitude, kind → DomainOperation_v25_kind |
| `DomainOperation_v25_client_ref` | `r_domain_operation_v25_client_ref` (scalar column) | string |
| `EpistemicAttitude` | `r_epistemic_attitude` | holder → RecordRef, proposition → RecordRef, attitude → EpistemicAttitudeKind, certainty → EpistemicAttitude_certainty, validity → Validity, basis → EvidenceBasis |
| `EpistemicAttitude_certainty` | `r_epistemic_attitude_certainty` | EpistemicAttitude_certainty_v0, EpistemicAttitude_certainty_v1 |
| `EpistemicAttitude_certainty_v0` | `r_epistemic_attitude_certainty_v0` (scalar column) | string |
| `EpistemicAttitude_certainty_v1` | `r_epistemic_attitude_certainty_v1` (scalar column) | null |
| `DomainOperation_v25_kind` | `r_domain_operation_v25_kind` (scalar column) | string |
| `DomainOperation_v26` | `r_domain_operation_v26` | client_ref → DomainOperation_v26_client_ref, record → Observation, kind → DomainOperation_v26_kind |
| `DomainOperation_v26_client_ref` | `r_domain_operation_v26_client_ref` (scalar column) | string |
| `Observation` | `r_observation` | observer → RecordRef, observed → RecordRef, sensoryAccess → Observation_sensoryAccess, time → TemporalExpression, interpretation → Observation_interpretation, basis → EvidenceBasis |
| `Observation_sensoryAccess` | `r_observation_sensory_access` (scalar column) | boolean |
| `Observation_interpretation` | `r_observation_interpretation` | RecordRef, Observation_interpretation_v1 |
| `Observation_interpretation_v1` | `r_observation_interpretation_v1` (scalar column) | null |
| `DomainOperation_v26_kind` | `r_domain_operation_v26_kind` (scalar column) | string |
| `DomainOperation_v27` | `r_domain_operation_v27` | client_ref → DomainOperation_v27_client_ref, record → Communication, kind → DomainOperation_v27_kind |
| `DomainOperation_v27_client_ref` | `r_domain_operation_v27_client_ref` (scalar column) | string |
| `Communication` | `r_communication` | sender → RecordRef, intendedRecipients → Communication_intendedRecipients, actualRecipients → Communication_actualRecipients, content → Communication_content, channel → Communication_channel, sentAt → TemporalExpression, receivedAt → Communication_receivedAt, distorted → Communication_distorted |
| `Communication_intendedRecipients` | `r_communication_intended_recipients` | RecordRef |
| `Communication_actualRecipients` | `r_communication_actual_recipients` | RecordRef |
| `Communication_content` | `r_communication_content` | RecordRef |
| `Communication_channel` | `r_communication_channel` | Communication_channel_v0, Communication_channel_v1 |
| `Communication_channel_v0` | `r_communication_channel_v0` (scalar column) | string |
| `Communication_channel_v1` | `r_communication_channel_v1` (scalar column) | null |
| `Communication_receivedAt` | `r_communication_received_at` | TemporalExpression, Communication_receivedAt_v1 |
| `Communication_receivedAt_v1` | `r_communication_received_at_v1` (scalar column) | null |
| `Communication_distorted` | `r_communication_distorted` (scalar column) | boolean |
| `DomainOperation_v27_kind` | `r_domain_operation_v27_kind` (scalar column) | string |
| `DomainOperation_v28` | `r_domain_operation_v28` | client_ref → DomainOperation_v28_client_ref, record → Memory, kind → DomainOperation_v28_kind |
| `DomainOperation_v28_client_ref` | `r_domain_operation_v28_client_ref` (scalar column) | string |
| `Memory` | `r_memory` | holder → RecordRef, content → RecordRef, alleged → Memory_alleged, accessibility → Memory_accessibility, altered → Memory_altered, validity → Validity |
| `Memory_alleged` | `r_memory_alleged` | RecordRef, Memory_alleged_v1 |
| `Memory_alleged_v1` | `r_memory_alleged_v1` (scalar column) | null |
| `Memory_accessibility` | `r_memory_accessibility` (scalar column) | string |
| `Memory_altered` | `r_memory_altered` (scalar column) | boolean |
| `DomainOperation_v28_kind` | `r_domain_operation_v28_kind` (scalar column) | string |
| `DomainOperation_v29` | `r_domain_operation_v29` | client_ref → DomainOperation_v29_client_ref, record → Goal, kind → DomainOperation_v29_kind |
| `DomainOperation_v29_client_ref` | `r_domain_operation_v29_client_ref` (scalar column) | string |
| `Goal` | `r_goal` | actor → RecordRef, desired → Goal_desired, prerequisites → Goal_prerequisites, steps → Goal_steps, status → PlanStatus, validity → Validity |
| `Goal_desired` | `r_goal_desired` | RecordRef, Goal_desired_v1 |
| `Goal_desired_v1` | `r_goal_desired_v1` (scalar column) | null |
| `Goal_prerequisites` | `r_goal_prerequisites` | Expr |
| `Goal_steps` | `r_goal_steps` | RecordRef |
| `DomainOperation_v29_kind` | `r_domain_operation_v29_kind` (scalar column) | string |
| `DomainOperation_v30` | `r_domain_operation_v30` | client_ref → DomainOperation_v30_client_ref, record → Commitment, kind → DomainOperation_v30_kind |
| `DomainOperation_v30_client_ref` | `r_domain_operation_v30_client_ref` (scalar column) | string |
| `Commitment` | `r_commitment` | parties → Commitment_parties, obligated → RecordRef, conditions → Commitment_conditions, deadline → Commitment_deadline, status → CommitmentStatus |
| `Commitment_parties` | `r_commitment_parties` | CommitmentParty |
| `Commitment_conditions` | `r_commitment_conditions` | Expr |
| `Commitment_deadline` | `r_commitment_deadline` | TemporalExpression, Commitment_deadline_v1 |
| `Commitment_deadline_v1` | `r_commitment_deadline_v1` (scalar column) | null |
| `DomainOperation_v30_kind` | `r_domain_operation_v30_kind` (scalar column) | string |
| `DomainOperation_v31` | `r_domain_operation_v31` | client_ref → DomainOperation_v31_client_ref, record → EntityType, kind → DomainOperation_v31_kind |
| `DomainOperation_v31_client_ref` | `r_domain_operation_v31_client_ref` (scalar column) | string |
| `EntityType` | `r_entity_type` | namespace → EntityType_namespace, key → EntityType_key, labels → EntityType_labels, parents → EntityType_parents, classificationExecutable → EntityType_classificationExecutable |
| `EntityType_namespace` | `r_entity_type_namespace` (scalar column) | string |
| `EntityType_key` | `r_entity_type_key` (scalar column) | string |
| `EntityType_labels` | `r_entity_type_labels` | EntityType_labels_item |
| `EntityType_labels_item` | `r_entity_type_labels_item` (scalar column) | string |
| `EntityType_parents` | `r_entity_type_parents` | RecordId |
| `EntityType_classificationExecutable` | `r_entity_type_classification_executable` (scalar column) | boolean |
| `DomainOperation_v31_kind` | `r_domain_operation_v31_kind` (scalar column) | string |
| `DomainOperation_v32` | `r_domain_operation_v32` | client_ref → DomainOperation_v32_client_ref, record → PropertyDef, kind → DomainOperation_v32_kind |
| `DomainOperation_v32_client_ref` | `r_domain_operation_v32_client_ref` (scalar column) | string |
| `PropertyDef` | `r_property_def` | namespace → PropertyDef_namespace, key → PropertyDef_key, labels → PropertyDef_labels, subjectTypes → PropertyDef_subjectTypes, value → ValueShape, multiplicity → Multiplicity, unitDimension → PropertyDef_unitDimension, persistence → PersistenceSemantics, exclusive → PropertyDef_exclusive, inverse → PropertyDef_inverse, symmetric → PropertyDef_symmetric, transitive → PropertyDef_transitive |
| `PropertyDef_namespace` | `r_property_def_namespace` (scalar column) | string |
| `PropertyDef_key` | `r_property_def_key` (scalar column) | string |
| `PropertyDef_labels` | `r_property_def_labels` | PropertyDef_labels_item |
| `PropertyDef_labels_item` | `r_property_def_labels_item` (scalar column) | string |
| `PropertyDef_subjectTypes` | `r_property_def_subject_types` | RecordId |
| `PropertyDef_unitDimension` | `r_property_def_unit_dimension` | PropertyDef_unitDimension_v0, PropertyDef_unitDimension_v1 |
| `PropertyDef_unitDimension_v0` | `r_property_def_unit_dimension_v0` (scalar column) | string |
| `PropertyDef_unitDimension_v1` | `r_property_def_unit_dimension_v1` (scalar column) | null |
| `PropertyDef_exclusive` | `r_property_def_exclusive` (scalar column) | boolean |
| `PropertyDef_inverse` | `r_property_def_inverse` | PropertyDef_inverse_v0, PropertyDef_inverse_v1 |
| `PropertyDef_inverse_v0` | `r_property_def_inverse_v0` (scalar column) | string |
| `PropertyDef_inverse_v1` | `r_property_def_inverse_v1` (scalar column) | null |
| `PropertyDef_symmetric` | `r_property_def_symmetric` (scalar column) | boolean |
| `PropertyDef_transitive` | `r_property_def_transitive` (scalar column) | boolean |
| `DomainOperation_v32_kind` | `r_domain_operation_v32_kind` (scalar column) | string |
| `DomainOperation_v33` | `r_domain_operation_v33` | client_ref → DomainOperation_v33_client_ref, record → RelationDef, kind → DomainOperation_v33_kind |
| `DomainOperation_v33_client_ref` | `r_domain_operation_v33_client_ref` (scalar column) | string |
| `RelationDef` | `r_relation_def` | namespace → RelationDef_namespace, key → RelationDef_key, labels → RelationDef_labels, roles → RelationDef_roles |
| `RelationDef_namespace` | `r_relation_def_namespace` (scalar column) | string |
| `RelationDef_key` | `r_relation_def_key` (scalar column) | string |
| `RelationDef_labels` | `r_relation_def_labels` | RelationDef_labels_item |
| `RelationDef_labels_item` | `r_relation_def_labels_item` (scalar column) | string |
| `RelationDef_roles` | `r_relation_def_roles` | RoleDef |
| `DomainOperation_v33_kind` | `r_domain_operation_v33_kind` (scalar column) | string |
| `DomainOperation_v34` | `r_domain_operation_v34` | client_ref → DomainOperation_v34_client_ref, record → UnitDef, kind → DomainOperation_v34_kind |
| `DomainOperation_v34_client_ref` | `r_domain_operation_v34_client_ref` (scalar column) | string |
| `UnitDef` | `r_unit_def` | namespace → UnitDef_namespace, key → UnitDef_key, dimension → UnitDef_dimension, symbol → UnitDef_symbol, labels → UnitDef_labels, scaleToBase → UnitDef_scaleToBase, base → UnitDef_base, validity → Validity |
| `UnitDef_namespace` | `r_unit_def_namespace` (scalar column) | string |
| `UnitDef_key` | `r_unit_def_key` (scalar column) | string |
| `UnitDef_dimension` | `r_unit_def_dimension` (scalar column) | string |
| `UnitDef_symbol` | `r_unit_def_symbol` (scalar column) | string |
| `UnitDef_labels` | `r_unit_def_labels` | UnitDef_labels_item |
| `UnitDef_labels_item` | `r_unit_def_labels_item` (scalar column) | string |
| `UnitDef_scaleToBase` | `r_unit_def_scale_to_base` | Value, UnitDef_scaleToBase_v1 |
| `UnitDef_scaleToBase_v1` | `r_unit_def_scale_to_base_v1` (scalar column) | null |
| `UnitDef_base` | `r_unit_def_base` | UnitId, UnitDef_base_v1 |
| `UnitDef_base_v1` | `r_unit_def_base_v1` (scalar column) | null |
| `DomainOperation_v34_kind` | `r_domain_operation_v34_kind` (scalar column) | string |
| `DomainOperation_v35` | `r_domain_operation_v35` | client_ref → DomainOperation_v35_client_ref, record → CalendarDef, kind → DomainOperation_v35_kind |
| `DomainOperation_v35_client_ref` | `r_domain_operation_v35_client_ref` (scalar column) | string |
| `CalendarDef` | `r_calendar_def` | namespace → CalendarDef_namespace, key → CalendarDef_key, labels → CalendarDef_labels, epoch → CalendarDef_epoch, unitStructure → CalendarDef_unitStructure, conversions → CalendarDef_conversions |
| `CalendarDef_namespace` | `r_calendar_def_namespace` (scalar column) | string |
| `CalendarDef_key` | `r_calendar_def_key` (scalar column) | string |
| `CalendarDef_labels` | `r_calendar_def_labels` | CalendarDef_labels_item |
| `CalendarDef_labels_item` | `r_calendar_def_labels_item` (scalar column) | string |
| `CalendarDef_epoch` | `r_calendar_def_epoch` | CalendarDef_epoch_v0, CalendarDef_epoch_v1 |
| `CalendarDef_epoch_v0` | `r_calendar_def_epoch_v0` (scalar column) | string |
| `CalendarDef_epoch_v1` | `r_calendar_def_epoch_v1` (scalar column) | null |
| `CalendarDef_unitStructure` | `r_calendar_def_unit_structure` | CalendarDef_unitStructure_item |
| `CalendarDef_unitStructure_item` | `r_calendar_def_unit_structure_item` (scalar column) | string |
| `CalendarDef_conversions` | `r_calendar_def_conversions` | CalendarConversion |
| `DomainOperation_v35_kind` | `r_domain_operation_v35_kind` (scalar column) | string |
| `DomainOperation_v36` | `r_domain_operation_v36` | client_ref → DomainOperation_v36_client_ref, record → ValueDef, kind → DomainOperation_v36_kind |
| `DomainOperation_v36_client_ref` | `r_domain_operation_v36_client_ref` (scalar column) | string |
| `ValueDef` | `r_value_def` | namespace → ValueDef_namespace, key → ValueDef_key, labels → ValueDef_labels, fields → ValueDef_fields |
| `ValueDef_namespace` | `r_value_def_namespace` (scalar column) | string |
| `ValueDef_key` | `r_value_def_key` (scalar column) | string |
| `ValueDef_labels` | `r_value_def_labels` | ValueDef_labels_item |
| `ValueDef_labels_item` | `r_value_def_labels_item` (scalar column) | string |
| `ValueDef_fields` | `r_value_def_fields` | ValueDefField |
| `DomainOperation_v36_kind` | `r_domain_operation_v36_kind` (scalar column) | string |
| `DomainOperation_v37` | `r_domain_operation_v37` | client_ref → DomainOperation_v37_client_ref, record → Rule, kind → DomainOperation_v37_kind |
| `DomainOperation_v37_client_ref` | `r_domain_operation_v37_client_ref` (scalar column) | string |
| `Rule` | `r_rule` | namespace → Rule_namespace, key → Rule_key, labels → Rule_labels, kind → RuleKind, commitPolicy → CommitPolicy, applicability → Applicability, subjectTypes → Rule_subjectTypes, targetPredicates → Rule_targetPredicates, expression → Expr, capabilities → Rule_capabilities, executable → Rule_executable, validity → Validity |
| `Rule_namespace` | `r_rule_namespace` (scalar column) | string |
| `Rule_key` | `r_rule_key` (scalar column) | string |
| `Rule_labels` | `r_rule_labels` | Rule_labels_item |
| `Rule_labels_item` | `r_rule_labels_item` (scalar column) | string |
| `Rule_subjectTypes` | `r_rule_subject_types` | RecordId |
| `Rule_targetPredicates` | `r_rule_target_predicates` | Rule_targetPredicates_item |
| `Rule_targetPredicates_item` | `r_rule_target_predicates_item` (scalar column) | string |
| `Rule_capabilities` | `r_rule_capabilities` | Rule_capabilities_item |
| `Rule_capabilities_item` | `r_rule_capabilities_item` (scalar column) | string |
| `Rule_executable` | `r_rule_executable` (scalar column) | boolean |
| `DomainOperation_v37_kind` | `r_domain_operation_v37_kind` (scalar column) | string |
| `DomainOperation_v38` | `r_domain_operation_v38` | client_ref → DomainOperation_v38_client_ref, record → CompletenessDecl, kind → DomainOperation_v38_kind |
| `DomainOperation_v38_client_ref` | `r_domain_operation_v38_client_ref` (scalar column) | string |
| `CompletenessDecl` | `r_completeness_decl` | subject → RecordRef, predicate → CompletenessDecl_predicate, members → CompletenessDecl_members, completeness → CompletenessKind, validity → Validity, scope → Scope |
| `CompletenessDecl_predicate` | `r_completeness_decl_predicate` (scalar column) | string |
| `CompletenessDecl_members` | `r_completeness_decl_members` | RecordRef |
| `DomainOperation_v38_kind` | `r_domain_operation_v38_kind` (scalar column) | string |
| `DomainOperation_v39` | `r_domain_operation_v39` | client_ref → DomainOperation_v39_client_ref, record → CreativeBoundary, kind → DomainOperation_v39_kind |
| `DomainOperation_v39_client_ref` | `r_domain_operation_v39_client_ref` (scalar column) | string |
| `CreativeBoundary` | `r_creative_boundary` | key → CreativeBoundary_key, area → BoundaryArea, mode → BoundaryMode, constraints → CreativeBoundary_constraints, validity → Validity, scope → Scope |
| `CreativeBoundary_key` | `r_creative_boundary_key` (scalar column) | string |
| `CreativeBoundary_constraints` | `r_creative_boundary_constraints` | Expr |
| `DomainOperation_v39_kind` | `r_domain_operation_v39_kind` (scalar column) | string |
| `DomainOperation_v40` | `r_domain_operation_v40` | client_ref → DomainOperation_v40_client_ref, record → Exception, kind → DomainOperation_v40_kind |
| `DomainOperation_v40_client_ref` | `r_domain_operation_v40_client_ref` (scalar column) | string |
| `Exception` | `r_exception` | rule → RecordRef, ruleVersion → Exception_ruleVersion, scope → Scope, validity → Validity, authorizingDecision → RecordRef, rationale → Exception_rationale |
| `Exception_ruleVersion` | `r_exception_rule_version` | RecordVersionId, Exception_ruleVersion_v1 |
| `Exception_ruleVersion_v1` | `r_exception_rule_version_v1` (scalar column) | null |
| `Exception_rationale` | `r_exception_rationale` (scalar column) | string |
| `DomainOperation_v40_kind` | `r_domain_operation_v40_kind` (scalar column) | string |
| `DomainOperation_v41` | `r_domain_operation_v41` | client_ref → DomainOperation_v41_client_ref, record → Anchor, kind → DomainOperation_v41_kind |
| `DomainOperation_v41_client_ref` | `r_domain_operation_v41_client_ref` (scalar column) | string |
| `Anchor` | `r_anchor` | sourceVersion → VersionRef, locator → AnchorLocator, excerptDigest → Anchor_excerptDigest, excerpt → Anchor_excerpt, context → Anchor_context |
| `Anchor_excerptDigest` | `r_anchor_excerpt_digest` (scalar column) | string |
| `Anchor_excerpt` | `r_anchor_excerpt` (scalar column) | string |
| `Anchor_context` | `r_anchor_context` | RecordRef, Anchor_context_v1 |
| `Anchor_context_v1` | `r_anchor_context_v1` (scalar column) | null |
| `DomainOperation_v41_kind` | `r_domain_operation_v41_kind` (scalar column) | string |
| `DomainOperation_v42` | `r_domain_operation_v42` | client_ref → DomainOperation_v42_client_ref, record → RecordKind, payload → Payload, kind → DomainOperation_v42_kind |
| `DomainOperation_v42_client_ref` | `r_domain_operation_v42_client_ref` (scalar column) | string |
| `RecordKind` | `r_record_kind` (scalar column) | string |
| `DomainOperation_v42_kind` | `r_domain_operation_v42_kind` (scalar column) | string |
| `DomainOperation_v43` | `r_domain_operation_v43` | client_ref → DomainOperation_v43_client_ref, record → IssueDecision, kind → DomainOperation_v43_kind |
| `DomainOperation_v43_client_ref` | `r_domain_operation_v43_client_ref` (scalar column) | string |
| `IssueDecision` | `r_issue_decision` | fingerprints → IssueDecision_fingerprints, mode → IssueDecisionMode, scope → IssueDecision_scope, rationale → IssueDecision_rationale, principal → PrincipalId |
| `IssueDecision_fingerprints` | `r_issue_decision_fingerprints` | FindingFingerprint |
| `IssueDecision_scope` | `r_issue_decision_scope` (scalar column) | string |
| `IssueDecision_rationale` | `r_issue_decision_rationale` (scalar column) | string |
| `DomainOperation_v43_kind` | `r_domain_operation_v43_kind` (scalar column) | string |
| `DomainOperation_v44` | `r_domain_operation_v44` | source → RecordVersion, expected_version → DomainOperation_v44_expected_version, kind → DomainOperation_v44_kind |
| `RecordVersion` | `r_record_version` | record_version_id → RecordVersionId, identity → RecordIdentity, payload_schema_version → RecordVersion_payload_schema_version, payload → Payload, payload_digest → PayloadDigest |
| `RecordIdentity` | `r_record_identity` | universe_id → UniverseId, record_id → RecordId, record_kind → RecordKind |
| `RecordVersion_payload_schema_version` | `r_record_version_payload_schema_version` (scalar column) | string |
| `PayloadDigest` | `r_payload_digest` (scalar column) | string |
| `DomainOperation_v44_expected_version` | `r_domain_operation_v44_expected_version` | RecordVersionId, DomainOperation_v44_expected_version_v1 |
| `DomainOperation_v44_expected_version_v1` | `r_domain_operation_v44_expected_version_v1` (scalar column) | null |
| `DomainOperation_v44_kind` | `r_domain_operation_v44_kind` (scalar column) | string |
| `DomainOperation_v45` | `r_domain_operation_v45` | record → RecordRef, expected_version → RecordVersionId, rationale → DomainOperation_v45_rationale, kind → DomainOperation_v45_kind |
| `DomainOperation_v45_rationale` | `r_domain_operation_v45_rationale` (scalar column) | string |
| `DomainOperation_v45_kind` | `r_domain_operation_v45_kind` (scalar column) | string |
| `DomainOperation_v46` | `r_domain_operation_v46` | source → RecordRef, source_version → RecordVersionId, target → RecordRef, target_version → RecordVersionId, rationale → DomainOperation_v46_rationale, kind → DomainOperation_v46_kind |
| `DomainOperation_v46_rationale` | `r_domain_operation_v46_rationale` (scalar column) | string |
| `DomainOperation_v46_kind` | `r_domain_operation_v46_kind` (scalar column) | string |
| `DomainOperation_v47` | `r_domain_operation_v47` | client_ref → DomainOperation_v47_client_ref, record → DomainPack, kind → DomainOperation_v47_kind |
| `DomainOperation_v47_client_ref` | `r_domain_operation_v47_client_ref` (scalar column) | string |
| `DomainPack` | `r_domain_pack` | key → DomainPack_key, version → DomainPack_version, dependencies → DomainPack_dependencies, capabilities → DomainPack_capabilities, records → DomainPack_records |
| `DomainPack_key` | `r_domain_pack_key` (scalar column) | string |
| `DomainPack_version` | `r_domain_pack_version` (scalar column) | string |
| `DomainPack_dependencies` | `r_domain_pack_dependencies` | DomainPack_dependencies_item |
| `DomainPack_dependencies_item` | `r_domain_pack_dependencies_item` (scalar column) | string |
| `DomainPack_capabilities` | `r_domain_pack_capabilities` | DomainPack_capabilities_item |
| `DomainPack_capabilities_item` | `r_domain_pack_capabilities_item` (scalar column) | string |
| `DomainPack_records` | `r_domain_pack_records` | RecordId |
| `DomainOperation_v47_kind` | `r_domain_operation_v47_kind` (scalar column) | string |
| `DomainOperation_v48` | `r_domain_operation_v48` | record → RecordRef, expected_version → RecordVersionId, replacement → Payload, kind → DomainOperation_v48_kind |
| `DomainOperation_v48_kind` | `r_domain_operation_v48_kind` (scalar column) | string |
| `DomainOperation_v49` | `r_domain_operation_v49` | record → RecordRef, expected_version → RecordVersionId, replacement → DomainPack, kind → DomainOperation_v49_kind |
| `DomainOperation_v49_kind` | `r_domain_operation_v49_kind` (scalar column) | string |
| `StoredContext` | `r_stored_context` | owner → StoredContext_owner, scope → StoredContext_scope, expires → StoredContext_expires, frame → Frame |
| `StoredContext_owner` | `r_stored_context_owner` (scalar column) | string |
| `StoredContext_scope` | `r_stored_context_scope` (scalar column) | string |
| `StoredContext_expires` | `r_stored_context_expires` (scalar column) | integer |
| `Frame` | `r_frame` | universe → UniverseId, continuity → ContinuityId, revision → RevisionId, context → RecordRef, time → FrameTime, perspective → Perspective, readerScene → Frame_readerScene, personalSequence → Frame_personalSequence |
| `FrameTime` | `r_frame_time` | FrameTime_v0, FrameTime_v1, FrameTime_v2 |
| `FrameTime_v0` | `r_frame_time_v0` | kind → FrameTime_v0_kind |
| `FrameTime_v0_kind` | `r_frame_time_v0_kind` (scalar column) | string |
| `FrameTime_v1` | `r_frame_time_v1` | time → TemporalExpression, kind → FrameTime_v1_kind |
| `FrameTime_v1_kind` | `r_frame_time_v1_kind` (scalar column) | string |
| `FrameTime_v2` | `r_frame_time_v2` | event → RecordRef, side → EventTimeSide, kind → FrameTime_v2_kind |
| `EventTimeSide` | `r_event_time_side` | EventTimeSide_v0, EventTimeSide_v1 |
| `EventTimeSide_v0` | `r_event_time_side_v0` (scalar column) | string |
| `EventTimeSide_v1` | `r_event_time_side_v1` (scalar column) | string |
| `FrameTime_v2_kind` | `r_frame_time_v2_kind` (scalar column) | string |
| `Perspective` | `r_perspective` | Perspective_v0, Perspective_v1, Perspective_v2, Perspective_v3 |
| `Perspective_v0` | `r_perspective_v0` (scalar column) | string |
| `Perspective_v1` | `r_perspective_v1` | character → RecordId |
| `Perspective_v2` | `r_perspective_v2` | narrator → RecordId |
| `Perspective_v3` | `r_perspective_v3` (scalar column) | string |
| `Frame_readerScene` | `r_frame_reader_scene` | RecordId, Frame_readerScene_v1 |
| `Frame_readerScene_v1` | `r_frame_reader_scene_v1` (scalar column) | null |
| `Frame_personalSequence` | `r_frame_personal_sequence` | Frame_personalSequence_v0, Frame_personalSequence_v1 |
| `Frame_personalSequence_v0` | `r_frame_personal_sequence_v0` (scalar column) | string |
| `Frame_personalSequence_v1` | `r_frame_personal_sequence_v1` (scalar column) | null |
| `StoredProposal` | `r_stored_proposal` | proposal → Proposal, owner → StoredProposal_owner, author_origin → StoredProposal_author_origin, changes → StoredProposal_changes, footprint → Footprint |
| `Proposal` | `r_proposal` | base_frame → Frame, world_scope → Proposal_world_scope, proposal_id → ProposalId, version → Proposal_version, digest → Proposal_digest, submission → Submission, operations → Proposal_operations, compiled_changes → Proposal_compiled_changes, rationale → Proposal_rationale, canonical → Proposal_canonical, operation_id → OperationId, withdrawn → Proposal_withdrawn |
| `Proposal_world_scope` | `r_proposal_world_scope` | WorldId, Proposal_world_scope_v1 |
| `Proposal_world_scope_v1` | `r_proposal_world_scope_v1` (scalar column) | null |
| `ProposalId` | `r_proposal_id` (scalar column) | string |
| `Proposal_version` | `r_proposal_version` (scalar column) | integer |
| `Proposal_digest` | `r_proposal_digest` (scalar column) | string |
| `Submission` | `r_submission` (scalar column) | string |
| `Proposal_operations` | `r_proposal_operations` | DomainOperation |
| `Proposal_compiled_changes` | `r_proposal_compiled_changes` | CompiledChange |
| `CompiledChange` | `r_compiled_change` | record_id → RecordId, expected → CompiledChange_expected, next → CompiledChange_next |
| `CompiledChange_expected` | `r_compiled_change_expected` | RecordVersionId, CompiledChange_expected_v1 |
| `CompiledChange_expected_v1` | `r_compiled_change_expected_v1` (scalar column) | null |
| `CompiledChange_next` | `r_compiled_change_next` | RecordVersion, CompiledChange_next_v1 |
| `CompiledChange_next_v1` | `r_compiled_change_next_v1` (scalar column) | null |
| `Proposal_rationale` | `r_proposal_rationale` (scalar column) | string |
| `Proposal_canonical` | `r_proposal_canonical` (scalar column) | boolean |
| `OperationId` | `r_operation_id` (scalar column) | string |
| `Proposal_withdrawn` | `r_proposal_withdrawn` (scalar column) | boolean |
| `StoredProposal_owner` | `r_stored_proposal_owner` (scalar column) | string |
| `StoredProposal_author_origin` | `r_stored_proposal_author_origin` (scalar column) | boolean |
| `StoredProposal_changes` | `r_stored_proposal_changes` | Assignment |
| `Assignment` | `r_assignment` | record_id → RecordId, expected → Assignment_expected, next → Assignment_next |
| `Assignment_expected` | `r_assignment_expected` | RecordVersionId, Assignment_expected_v1 |
| `Assignment_expected_v1` | `r_assignment_expected_v1` (scalar column) | null |
| `Assignment_next` | `r_assignment_next` | RecordVersion, Assignment_next_v1 |
| `Assignment_next_v1` | `r_assignment_next_v1` (scalar column) | null |
| `Footprint` | `r_footprint` | worlds → Footprint_worlds, shared → Footprint_shared, protected → Footprint_protected |
| `Footprint_worlds` | `r_footprint_worlds` | WorldId |
| `Footprint_shared` | `r_footprint_shared` (scalar column) | boolean |
| `Footprint_protected` | `r_footprint_protected` (scalar column) | boolean |
| `Checked` | `r_checked` | proposal_digest → Checked_proposal_digest, validation → Validation, admissible → Checked_admissible, report → Checked_report, capture → Checked_capture |
| `Checked_proposal_digest` | `r_checked_proposal_digest` (scalar column) | string |
| `Validation` | `r_validation` | operation_id → Validation_operation_id, run_id → ValidationRunId, coverage → Coverage, findings → Validation_findings, opposing_evidence → Validation_opposing_evidence, unsupported_capabilities → Validation_unsupported_capabilities, input_digest → Validation_input_digest, evaluator_version → Validation_evaluator_version |
| `Validation_operation_id` | `r_validation_operation_id` | OperationId, Validation_operation_id_v1 |
| `Validation_operation_id_v1` | `r_validation_operation_id_v1` (scalar column) | null |
| `ValidationRunId` | `r_validation_run_id` (scalar column) | string |
| `Coverage` | `r_coverage` (scalar column) | string |
| `Validation_findings` | `r_validation_findings` | Finding |
| `Finding` | `r_finding` | fingerprint → FindingFingerprint, rule_id → RecordId, outcome → EvidenceOutcome, evidence → Finding_evidence, coverage → Coverage |
| `EvidenceOutcome` | `r_evidence_outcome` (scalar column) | string |
| `Finding_evidence` | `r_finding_evidence` | RecordVersionId |
| `Validation_opposing_evidence` | `r_validation_opposing_evidence` | OpposingEvidence |
| `OpposingEvidence` | `r_opposing_evidence` | diagnostic_version → OpposingEvidence_diagnostic_version, fingerprint → FindingFingerprint, kind → OpposingKind, proposition → Proposition, support → OpposingChain, refutation → OpposingChain, context → RecordRef, applicability → OpposingEvidence_applicability, realm → OpposingEvidence_realm, intersection → OpposingIntersection, coverage → Coverage, unresolved_reasons → OpposingEvidence_unresolved_reasons, policy_versions → OpposingEvidence_policy_versions, exception_versions → OpposingEvidence_exception_versions |
| `OpposingEvidence_diagnostic_version` | `r_opposing_evidence_diagnostic_version` (scalar column) | string |
| `OpposingKind` | `r_opposing_kind` (scalar column) | string |
| `OpposingChain` | `r_opposing_chain` | assertion_id → RecordId, proposition_id → RecordId, assertion → RecordVersionId, proposition → RecordVersionId, dependencies → OpposingChain_dependencies, complete → OpposingChain_complete |
| `OpposingChain_dependencies` | `r_opposing_chain_dependencies` | VersionRef |
| `OpposingChain_complete` | `r_opposing_chain_complete` (scalar column) | boolean |
| `OpposingEvidence_applicability` | `r_opposing_evidence_applicability` | Applicability, OpposingEvidence_applicability_v1 |
| `OpposingEvidence_applicability_v1` | `r_opposing_evidence_applicability_v1` (scalar column) | null |
| `OpposingEvidence_realm` | `r_opposing_evidence_realm` | RecordRef, OpposingEvidence_realm_v1 |
| `OpposingEvidence_realm_v1` | `r_opposing_evidence_realm_v1` (scalar column) | null |
| `OpposingIntersection` | `r_opposing_intersection` | OpposingIntersection_v0, OpposingIntersection_v1, OpposingIntersection_v2, OpposingIntersection_v3 |
| `OpposingIntersection_v0` | `r_opposing_intersection_v0` | kind → OpposingIntersection_v0_kind |
| `OpposingIntersection_v0_kind` | `r_opposing_intersection_v0_kind` (scalar column) | string |
| `OpposingIntersection_v1` | `r_opposing_intersection_v1` | validity → Validity, kind → OpposingIntersection_v1_kind |
| `OpposingIntersection_v1_kind` | `r_opposing_intersection_v1_kind` (scalar column) | string |
| `OpposingIntersection_v2` | `r_opposing_intersection_v2` | left → Validity, right → Validity, guaranteed → OpposingIntersection_v2_guaranteed, kind → OpposingIntersection_v2_kind |
| `OpposingIntersection_v2_guaranteed` | `r_opposing_intersection_v2_guaranteed` | Validity, OpposingIntersection_v2_guaranteed_v1 |
| `OpposingIntersection_v2_guaranteed_v1` | `r_opposing_intersection_v2_guaranteed_v1` (scalar column) | null |
| `OpposingIntersection_v2_kind` | `r_opposing_intersection_v2_kind` (scalar column) | string |
| `OpposingIntersection_v3` | `r_opposing_intersection_v3` | kind → OpposingIntersection_v3_kind |
| `OpposingIntersection_v3_kind` | `r_opposing_intersection_v3_kind` (scalar column) | string |
| `OpposingEvidence_unresolved_reasons` | `r_opposing_evidence_unresolved_reasons` | OpposingReason |
| `OpposingReason` | `r_opposing_reason` (scalar column) | string |
| `OpposingEvidence_policy_versions` | `r_opposing_evidence_policy_versions` | RecordVersionId |
| `OpposingEvidence_exception_versions` | `r_opposing_evidence_exception_versions` | RecordVersionId |
| `Validation_unsupported_capabilities` | `r_validation_unsupported_capabilities` | Validation_unsupported_capabilities_item |
| `Validation_unsupported_capabilities_item` | `r_validation_unsupported_capabilities_item` (scalar column) | string |
| `Validation_input_digest` | `r_validation_input_digest` (scalar column) | string |
| `Validation_evaluator_version` | `r_validation_evaluator_version` (scalar column) | string |
| `Checked_admissible` | `r_checked_admissible` (scalar column) | boolean |
| `Checked_report` | `r_checked_report` | ValidationV3, Checked_report_v1 |
| `ValidationV3` | `r_validation_v3` | ValidationV3_v0, ValidationV3_v1 |
| `ValidationV3_v0` | `r_validation_v3_v0` | execution → Validation, submitted_input → SubmittedInput, assessment → AssessmentState, final_binding_digest → ValidationV3_v0_final_binding_digest, kind → ValidationV3_v0_kind |
| `SubmittedInput` | `r_submitted_input` | SubmittedInput_v0, SubmittedInput_v1, SubmittedInput_v2 |
| `SubmittedInput_v0` | `r_submitted_input_v0` | frame → Frame, check_scope → CheckScope, kind → SubmittedInput_v0_kind |
| `CheckScope` | `r_check_scope` (scalar column) | string |
| `SubmittedInput_v0_kind` | `r_submitted_input_v0_kind` (scalar column) | string |
| `SubmittedInput_v1` | `r_submitted_input_v1` | proposal → ProposalRef, includes_sources → SubmittedInput_v1_includes_sources, kind → SubmittedInput_v1_kind |
| `ProposalRef` | `r_proposal_ref` | proposal_id → ProposalId, version → ProposalRef_version, digest → ProposalRef_digest |
| `ProposalRef_version` | `r_proposal_ref_version` (scalar column) | integer |
| `ProposalRef_digest` | `r_proposal_ref_digest` (scalar column) | string |
| `SubmittedInput_v1_includes_sources` | `r_submitted_input_v1_includes_sources` (scalar column) | boolean |
| `SubmittedInput_v1_kind` | `r_submitted_input_v1_kind` (scalar column) | string |
| `SubmittedInput_v2` | `r_submitted_input_v2` | proposal → ProposalRef, sources → SubmittedInput_v2_sources, inventory_digest → Sha256Hex, kind → SubmittedInput_v2_kind |
| `SubmittedInput_v2_sources` | `r_submitted_input_v2_sources` | SourceBinding |
| `SourceBinding` | `r_source_binding` | key → SourceBinding_key, source_version → AssessmentVersionRef, blob_digest → Sha256Hex, byte_size → SourceBinding_byte_size, representation → SourceRepresentation, ranges → SourceBinding_ranges, work_edition → SourceBinding_work_edition, passage_id → SourceBinding_passage_id |
| `SourceBinding_key` | `r_source_binding_key` (scalar column) | string |
| `AssessmentVersionRef` | `r_assessment_version_ref` | universe → UniverseId, record → RecordId, version → RecordVersionId |
| `Sha256Hex` | `r_sha256_hex` (scalar column) | string |
| `SourceBinding_byte_size` | `r_source_binding_byte_size` (scalar column) | integer |
| `SourceRepresentation` | `r_source_representation` (scalar column) | string |
| `SourceBinding_ranges` | `r_source_binding_ranges` | ByteRange |
| `ByteRange` | `r_byte_range` | start → ByteRange_start, end → ByteRange_end |
| `ByteRange_start` | `r_byte_range_start` (scalar column) | integer |
| `ByteRange_end` | `r_byte_range_end` (scalar column) | integer |
| `SourceBinding_work_edition` | `r_source_binding_work_edition` | AssessmentVersionRef, SourceBinding_work_edition_v1 |
| `SourceBinding_work_edition_v1` | `r_source_binding_work_edition_v1` (scalar column) | null |
| `SourceBinding_passage_id` | `r_source_binding_passage_id` | SourceBinding_passage_id_v0, SourceBinding_passage_id_v1 |
| `SourceBinding_passage_id_v0` | `r_source_binding_passage_id_v0` (scalar column) | string |
| `SourceBinding_passage_id_v1` | `r_source_binding_passage_id_v1` (scalar column) | null |
| `SubmittedInput_v2_kind` | `r_submitted_input_v2_kind` (scalar column) | string |
| `AssessmentState` | `r_assessment_state` | AssessmentState_v0, AssessmentState_v1, AssessmentState_v2, AssessmentState_v3, AssessmentState_v4 |
| `AssessmentState_v0` | `r_assessment_state_v0` | kind → AssessmentState_v0_kind |
| `AssessmentState_v0_kind` | `r_assessment_state_v0_kind` (scalar column) | string |
| `AssessmentState_v1` | `r_assessment_state_v1` | kind → AssessmentState_v1_kind |
| `AssessmentState_v1_kind` | `r_assessment_state_v1_kind` (scalar column) | string |
| `AssessmentState_v2` | `r_assessment_state_v2` | reason → UnavailableReason, kind → AssessmentState_v2_kind |
| `UnavailableReason` | `r_unavailable_reason` (scalar column) | string |
| `AssessmentState_v2_kind` | `r_assessment_state_v2_kind` (scalar column) | string |
| `AssessmentState_v3` | `r_assessment_state_v3` | assessment_reference → AssessmentRef, reasons → AssessmentState_v3_reasons, kind → AssessmentState_v3_kind |
| `AssessmentRef` | `r_assessment_ref` | assessment_id → AssessmentId, digest → Sha256Hex |
| `AssessmentId` | `r_assessment_id` (scalar column) | string |
| `AssessmentState_v3_reasons` | `r_assessment_state_v3_reasons` | StaleReason |
| `StaleReason` | `r_stale_reason` (scalar column) | string |
| `AssessmentState_v3_kind` | `r_assessment_state_v3_kind` (scalar column) | string |
| `AssessmentState_v4` | `r_assessment_state_v4` | assessment_reference → AssessmentRef, selection_generation → AssessmentState_v4_selection_generation, byte_verification → ByteVerification, declared_conclusion → DeclaredConclusion, inventory_count → AssessmentState_v4_inventory_count, mapping_count → AssessmentState_v4_mapping_count, unresolved_count → AssessmentState_v4_unresolved_count, inventory_digest → Sha256Hex, kind → AssessmentState_v4_kind |
| `AssessmentState_v4_selection_generation` | `r_assessment_state_v4_selection_generation` (scalar column) | integer |
| `ByteVerification` | `r_byte_verification` (scalar column) | string |
| `DeclaredConclusion` | `r_declared_conclusion` (scalar column) | string |
| `AssessmentState_v4_inventory_count` | `r_assessment_state_v4_inventory_count` (scalar column) | integer |
| `AssessmentState_v4_mapping_count` | `r_assessment_state_v4_mapping_count` (scalar column) | integer |
| `AssessmentState_v4_unresolved_count` | `r_assessment_state_v4_unresolved_count` (scalar column) | integer |
| `AssessmentState_v4_kind` | `r_assessment_state_v4_kind` (scalar column) | string |
| `ValidationV3_v0_final_binding_digest` | `r_validation_v3_v0_final_binding_digest` | Sha256Hex, ValidationV3_v0_final_binding_digest_v1 |
| `ValidationV3_v0_final_binding_digest_v1` | `r_validation_v3_v0_final_binding_digest_v1` (scalar column) | null |
| `ValidationV3_v0_kind` | `r_validation_v3_v0_kind` (scalar column) | string |
| `ValidationV3_v1` | `r_validation_v3_v1` | execution_coverage → RestrictedCoverage, submitted_input → RestrictedInput, assessment → RestrictedAssessment, kind → ValidationV3_v1_kind |
| `RestrictedCoverage` | `r_restricted_coverage` (scalar column) | string |
| `RestrictedInput` | `r_restricted_input` | RestrictedInput_v0 |
| `RestrictedInput_v0` | `r_restricted_input_v0` | kind → RestrictedInput_v0_kind |
| `RestrictedInput_v0_kind` | `r_restricted_input_v0_kind` (scalar column) | string |
| `RestrictedAssessment` | `r_restricted_assessment` | RestrictedAssessment_v0 |
| `RestrictedAssessment_v0` | `r_restricted_assessment_v0` | kind → RestrictedAssessment_v0_kind |
| `RestrictedAssessment_v0_kind` | `r_restricted_assessment_v0_kind` (scalar column) | string |
| `ValidationV3_v1_kind` | `r_validation_v3_v1_kind` (scalar column) | string |
| `Checked_report_v1` | `r_checked_report_v1` (scalar column) | null |
| `Checked_capture` | `r_checked_capture` | ValidationCapture, Checked_capture_v1 |
| `ValidationCapture` | `r_validation_capture` | selection → AssessmentSelection, assessment → AssessmentState, submitted_input → SubmittedInput, head → RevisionId, latest_proposal_key → ValidationCapture_latest_proposal_key, authority_digest → ValidationCapture_authority_digest, authority_sequence → ValidationCapture_authority_sequence |
| `AssessmentSelection` | `r_assessment_selection` | proposal → AssessmentSelection_proposal, generation → AssessmentSelection_generation, selected → AssessmentSelection_selected |
| `AssessmentSelection_proposal` | `r_assessment_selection_proposal` | proposal_id → ProposalId, version → AssessmentSelection_proposal_version, digest → Sha256Hex |
| `AssessmentSelection_proposal_version` | `r_assessment_selection_proposal_version` (scalar column) | integer |
| `AssessmentSelection_generation` | `r_assessment_selection_generation` (scalar column) | integer |
| `AssessmentSelection_selected` | `r_assessment_selection_selected` | AssessmentRef, AssessmentSelection_selected_v1 |
| `AssessmentSelection_selected_v1` | `r_assessment_selection_selected_v1` (scalar column) | null |
| `ValidationCapture_latest_proposal_key` | `r_validation_capture_latest_proposal_key` | ValidationCapture_latest_proposal_key_v0, ValidationCapture_latest_proposal_key_v1 |
| `ValidationCapture_latest_proposal_key_v0` | `r_validation_capture_latest_proposal_key_v0` (scalar column) | string |
| `ValidationCapture_latest_proposal_key_v1` | `r_validation_capture_latest_proposal_key_v1` (scalar column) | null |
| `ValidationCapture_authority_digest` | `r_validation_capture_authority_digest` (scalar column) | string |
| `ValidationCapture_authority_sequence` | `r_validation_capture_authority_sequence` | ValidationCapture_authority_sequence_v0, ValidationCapture_authority_sequence_v1 |
| `ValidationCapture_authority_sequence_v0` | `r_validation_capture_authority_sequence_v0` (scalar column) | integer |
| `ValidationCapture_authority_sequence_v1` | `r_validation_capture_authority_sequence_v1` (scalar column) | null |
| `Checked_capture_v1` | `r_checked_capture_v1` (scalar column) | null |
| `StoredOperation` | `r_stored_operation` | owner → StoredOperation_owner, digest → StoredOperation_digest, status → OperationStatusInternal, input → StoredOperation_input, footprint → Footprint, validation_capture → StoredOperation_validation_capture |
| `StoredOperation_owner` | `r_stored_operation_owner` (scalar column) | string |
| `StoredOperation_digest` | `r_stored_operation_digest` (scalar column) | string |
| `OperationStatusInternal` | `r_operation_status_internal` | validation → OperationStatusInternal_validation, failure → OperationStatusInternal_failure, operation_id → OperationId, kind → OperationKind, state → OperationState, proposal → OperationStatusInternal_proposal, receipt → OperationStatusInternal_receipt, cancellation_requested → OperationStatusInternal_cancellation_requested |
| `OperationStatusInternal_validation` | `r_operation_status_internal_validation` | Validation, OperationStatusInternal_validation_v1 |
| `OperationStatusInternal_validation_v1` | `r_operation_status_internal_validation_v1` (scalar column) | null |
| `OperationStatusInternal_failure` | `r_operation_status_internal_failure` | OperationStatusInternal_failure_v0, OperationStatusInternal_failure_v1 |
| `OperationStatusInternal_failure_v0` | `r_operation_status_internal_failure_v0` (scalar column) | string |
| `OperationStatusInternal_failure_v1` | `r_operation_status_internal_failure_v1` (scalar column) | null |
| `OperationKind` | `r_operation_kind` (scalar column) | string |
| `OperationState` | `r_operation_state` (scalar column) | string |
| `OperationStatusInternal_proposal` | `r_operation_status_internal_proposal` | Proposal, OperationStatusInternal_proposal_v1 |
| `OperationStatusInternal_proposal_v1` | `r_operation_status_internal_proposal_v1` (scalar column) | null |
| `OperationStatusInternal_receipt` | `r_operation_status_internal_receipt` | CommitReceipt, OperationStatusInternal_receipt_v1 |
| `CommitReceipt` | `r_commit_receipt` | operation_id → OperationId, proposal_id → ProposalId, revision → RevisionId |
| `OperationStatusInternal_receipt_v1` | `r_operation_status_internal_receipt_v1` (scalar column) | null |
| `OperationStatusInternal_cancellation_requested` | `r_operation_status_internal_cancellation_requested` (scalar column) | boolean |
| `StoredOperation_input` | `r_stored_operation_input` | CommitInput, StoredOperation_input_v1 |
| `CommitInput` | `r_commit_input` | universe → UniverseId, continuity → ContinuityId, expected_head → RevisionId, principal → PrincipalId, decision → CommitInput_decision, reason → CommitInput_reason, idempotency_key → CommitInput_idempotency_key, changes → CommitInput_changes |
| `CommitInput_decision` | `r_commit_input_decision` (scalar column) | string |
| `CommitInput_reason` | `r_commit_input_reason` (scalar column) | string |
| `CommitInput_idempotency_key` | `r_commit_input_idempotency_key` (scalar column) | string |
| `CommitInput_changes` | `r_commit_input_changes` | Assignment |
| `StoredOperation_input_v1` | `r_stored_operation_input_v1` (scalar column) | null |
| `StoredOperation_validation_capture` | `r_stored_operation_validation_capture` | ValidationCapture, StoredOperation_validation_capture_v1 |
| `StoredOperation_validation_capture_v1` | `r_stored_operation_validation_capture_v1` (scalar column) | null |
| `ApprovalEvidence` | `r_approval_evidence` | author → ApprovalEvidence_author, proposal → ProposalRef, validation_digest → ApprovalEvidence_validation_digest, evaluator → ApprovalEvidence_evaluator |
| `ApprovalEvidence_author` | `r_approval_evidence_author` (scalar column) | string |
| `ApprovalEvidence_validation_digest` | `r_approval_evidence_validation_digest` (scalar column) | string |
| `ApprovalEvidence_evaluator` | `r_approval_evidence_evaluator` (scalar column) | string |
| `AssessmentEnvelope` | `r_assessment_envelope` | assessment_id → AssessmentId, digest → Sha256Hex, body → SourceAssessmentV1 |
| `SourceAssessmentV1` | `r_source_assessment_v1` | kind → AssessmentKind, proposal → SourceAssessmentV1_proposal, base_frame → Frame, assessor → Assessor, sources → SourceAssessmentV1_sources, dependencies → SourceAssessmentV1_dependencies, declared_inventory → SourceAssessmentV1_declared_inventory, inventory_declaration → InventoryDeclaration, claim_mappings → SourceAssessmentV1_claim_mappings, unresolved → SourceAssessmentV1_unresolved, conclusion → DeclaredConclusion |
| `AssessmentKind` | `r_assessment_kind` (scalar column) | string |
| `SourceAssessmentV1_proposal` | `r_source_assessment_v1_proposal` | proposal_id → ProposalId, version → SourceAssessmentV1_proposal_version, digest → Sha256Hex |
| `SourceAssessmentV1_proposal_version` | `r_source_assessment_v1_proposal_version` (scalar column) | integer |
| `Assessor` | `r_assessor` | principal → PrincipalId, method → Method, tool → Assessor_tool, assessed_at → Assessor_assessed_at |
| `Method` | `r_method` (scalar column) | string |
| `Assessor_tool` | `r_assessor_tool` | ToolIdentity, Assessor_tool_v1 |
| `ToolIdentity` | `r_tool_identity` | name → ToolIdentity_name, version → ToolIdentity_version, model_revision → ToolIdentity_model_revision, procedure_digest → Sha256Hex |
| `ToolIdentity_name` | `r_tool_identity_name` (scalar column) | string |
| `ToolIdentity_version` | `r_tool_identity_version` (scalar column) | string |
| `ToolIdentity_model_revision` | `r_tool_identity_model_revision` (scalar column) | string |
| `Assessor_tool_v1` | `r_assessor_tool_v1` (scalar column) | null |
| `Assessor_assessed_at` | `r_assessor_assessed_at` (scalar column) | string |
| `SourceAssessmentV1_sources` | `r_source_assessment_v1_sources` | SourceBinding |
| `SourceAssessmentV1_dependencies` | `r_source_assessment_v1_dependencies` | AssessmentVersionRef |
| `SourceAssessmentV1_declared_inventory` | `r_source_assessment_v1_declared_inventory` | MaterialItem |
| `MaterialItem` | `r_material_item` | item_id → MaterialItem_item_id, source_key → MaterialItem_source_key, range → ByteRange, material_kind → MaterialKind, statement → MaterialItem_statement, mapping_ids → MaterialItem_mapping_ids, unresolved_ids → MaterialItem_unresolved_ids |
| `MaterialItem_item_id` | `r_material_item_item_id` (scalar column) | string |
| `MaterialItem_source_key` | `r_material_item_source_key` (scalar column) | string |
| `MaterialKind` | `r_material_kind` (scalar column) | string |
| `MaterialItem_statement` | `r_material_item_statement` (scalar column) | string |
| `MaterialItem_mapping_ids` | `r_material_item_mapping_ids` | MaterialItem_mapping_ids_item |
| `MaterialItem_mapping_ids_item` | `r_material_item_mapping_ids_item` (scalar column) | string |
| `MaterialItem_unresolved_ids` | `r_material_item_unresolved_ids` | MaterialItem_unresolved_ids_item |
| `MaterialItem_unresolved_ids_item` | `r_material_item_unresolved_ids_item` (scalar column) | string |
| `InventoryDeclaration` | `r_inventory_declaration` | kind → InventoryKind, rationale → InventoryDeclaration_rationale, exclusions → InventoryDeclaration_exclusions |
| `InventoryKind` | `r_inventory_kind` (scalar column) | string |
| `InventoryDeclaration_rationale` | `r_inventory_declaration_rationale` (scalar column) | string |
| `InventoryDeclaration_exclusions` | `r_inventory_declaration_exclusions` | Exclusion |
| `Exclusion` | `r_exclusion` | source_key → Exclusion_source_key, range → ByteRange, reason → Exclusion_reason |
| `Exclusion_source_key` | `r_exclusion_source_key` (scalar column) | string |
| `Exclusion_reason` | `r_exclusion_reason` (scalar column) | string |
| `SourceAssessmentV1_claim_mappings` | `r_source_assessment_v1_claim_mappings` | ClaimMapping |
| `ClaimMapping` | `r_claim_mapping` | mapping_id → ClaimMapping_mapping_id, item_ids → ClaimMapping_item_ids, referents → ClaimMapping_referents, context → AssessmentVersionRef, world → ClaimMapping_world, realm → ClaimMapping_realm, story_time → TemporalExpression, narration_position → Position, reader_position → Position, occurrence → Occurrence, modality → Modality, semantic → SemanticMapping, candidate_links → ClaimMapping_candidate_links, judgment → MappingJudgment, rationale → ClaimMapping_rationale |
| `ClaimMapping_mapping_id` | `r_claim_mapping_mapping_id` (scalar column) | string |
| `ClaimMapping_item_ids` | `r_claim_mapping_item_ids` | ClaimMapping_item_ids_item |
| `ClaimMapping_item_ids_item` | `r_claim_mapping_item_ids_item` (scalar column) | string |
| `ClaimMapping_referents` | `r_claim_mapping_referents` | AssessmentVersionRef |
| `ClaimMapping_world` | `r_claim_mapping_world` | AssessmentVersionRef, ClaimMapping_world_v1 |
| `ClaimMapping_world_v1` | `r_claim_mapping_world_v1` (scalar column) | null |
| `ClaimMapping_realm` | `r_claim_mapping_realm` | AssessmentVersionRef, ClaimMapping_realm_v1 |
| `ClaimMapping_realm_v1` | `r_claim_mapping_realm_v1` (scalar column) | null |
| `Position` | `r_position` | Position_v0, Position_v1, Position_v2 |
| `Position_v0` | `r_position_v0` | kind → Position_v0_kind |
| `Position_v0_kind` | `r_position_v0_kind` (scalar column) | string |
| `Position_v1` | `r_position_v1` | reason → Position_v1_reason, kind → Position_v1_kind |
| `Position_v1_reason` | `r_position_v1_reason` (scalar column) | string |
| `Position_v1_kind` | `r_position_v1_kind` (scalar column) | string |
| `Position_v2` | `r_position_v2` | work_edition → AssessmentVersionRef, scene_id → Position_v2_scene_id, ordinal → Position_v2_ordinal, kind → Position_v2_kind |
| `Position_v2_scene_id` | `r_position_v2_scene_id` (scalar column) | string |
| `Position_v2_ordinal` | `r_position_v2_ordinal` (scalar column) | integer |
| `Position_v2_kind` | `r_position_v2_kind` (scalar column) | string |
| `Occurrence` | `r_occurrence` (scalar column) | string |
| `Modality` | `r_modality` (scalar column) | string |
| `SemanticMapping` | `r_semantic_mapping` | SemanticMapping_v0, SemanticMapping_v1, SemanticMapping_v2, SemanticMapping_v3 |
| `SemanticMapping_v0` | `r_semantic_mapping_v0` | predicate → AssessmentVersionRef, subject → AssessmentVersionRef, value → Value, roles → SemanticMapping_v0_roles, polarity → Polarity, kind → SemanticMapping_v0_kind |
| `SemanticMapping_v0_roles` | `r_semantic_mapping_v0_roles` | RoleParticipant |
| `RoleParticipant` | `r_role_participant` | role → RoleParticipant_role, participant → AssessmentVersionRef |
| `RoleParticipant_role` | `r_role_participant_role` (scalar column) | string |
| `SemanticMapping_v0_kind` | `r_semantic_mapping_v0_kind` (scalar column) | string |
| `SemanticMapping_v1` | `r_semantic_mapping_v1` | action → AssessmentVersionRef, participants → SemanticMapping_v1_participants, prerequisites → SemanticMapping_v1_prerequisites, effects → SemanticMapping_v1_effects, kind → SemanticMapping_v1_kind |
| `SemanticMapping_v1_participants` | `r_semantic_mapping_v1_participants` | RoleParticipant |
| `SemanticMapping_v1_prerequisites` | `r_semantic_mapping_v1_prerequisites` | AssessmentVersionRef |
| `SemanticMapping_v1_effects` | `r_semantic_mapping_v1_effects` | AssessmentVersionRef |
| `SemanticMapping_v1_kind` | `r_semantic_mapping_v1_kind` (scalar column) | string |
| `SemanticMapping_v2` | `r_semantic_mapping_v2` | holder → AssessmentVersionRef, content → AssessmentVersionRef, acquisition → SemanticMapping_v2_acquisition, kind → SemanticMapping_v2_kind |
| `SemanticMapping_v2_acquisition` | `r_semantic_mapping_v2_acquisition` | AssessmentVersionRef |
| `SemanticMapping_v2_kind` | `r_semantic_mapping_v2_kind` (scalar column) | string |
| `SemanticMapping_v3` | `r_semantic_mapping_v3` | subject → AssessmentVersionRef, depiction → Depiction, implied_claims → SemanticMapping_v3_implied_claims, kind → SemanticMapping_v3_kind |
| `Depiction` | `r_depiction` (scalar column) | string |
| `SemanticMapping_v3_implied_claims` | `r_semantic_mapping_v3_implied_claims` | AssessmentVersionRef |
| `SemanticMapping_v3_kind` | `r_semantic_mapping_v3_kind` (scalar column) | string |
| `ClaimMapping_candidate_links` | `r_claim_mapping_candidate_links` | CandidateLink |
| `CandidateLink` | `r_candidate_link` | kind → CandidateLinkKind, version → AssessmentVersionRef |
| `CandidateLinkKind` | `r_candidate_link_kind` (scalar column) | string |
| `MappingJudgment` | `r_mapping_judgment` (scalar column) | string |
| `ClaimMapping_rationale` | `r_claim_mapping_rationale` (scalar column) | string |
| `SourceAssessmentV1_unresolved` | `r_source_assessment_v1_unresolved` | UnresolvedDisposition |
| `UnresolvedDisposition` | `r_unresolved_disposition` | unresolved_id → UnresolvedDisposition_unresolved_id, item_ids → UnresolvedDisposition_item_ids, reason → UnresolvedReason, detail → UnresolvedDisposition_detail |
| `UnresolvedDisposition_unresolved_id` | `r_unresolved_disposition_unresolved_id` (scalar column) | string |
| `UnresolvedDisposition_item_ids` | `r_unresolved_disposition_item_ids` | UnresolvedDisposition_item_ids_item |
| `UnresolvedDisposition_item_ids_item` | `r_unresolved_disposition_item_ids_item` (scalar column) | string |
| `UnresolvedReason` | `r_unresolved_reason` (scalar column) | string |
| `UnresolvedDisposition_detail` | `r_unresolved_disposition_detail` (scalar column) | string |
| `AssessmentReceipt` | `r_assessment_receipt` | request_digest → AssessmentReceipt_request_digest, selection → AssessmentSelection, envelope → AssessmentReceipt_envelope |
| `AssessmentReceipt_request_digest` | `r_assessment_receipt_request_digest` (scalar column) | string |
| `AssessmentReceipt_envelope` | `r_assessment_receipt_envelope` | AssessmentEnvelope, AssessmentReceipt_envelope_v1 |
| `AssessmentReceipt_envelope_v1` | `r_assessment_receipt_envelope_v1` (scalar column) | null |
| `Cursor` | `r_cursor` | binding → Cursor_binding, offset → Cursor_offset |
| `Cursor_binding` | `r_cursor_binding` (scalar column) | string |
| `Cursor_offset` | `r_cursor_offset` (scalar column) | integer |
| `Cancellation` | `r_cancellation` | owner → Cancellation_owner, cancelled → Cancellation_cancelled |
| `Cancellation_owner` | `r_cancellation_owner` (scalar column) | string |
| `Cancellation_cancelled` | `r_cancellation_cancelled` (scalar column) | boolean |
| `ReservedRecord` | `r_reserved_record` | proposal_id → ProposalId |
| `SavedDraft` | `r_saved_draft` | version → SavedDraft_version, content → DraftContent |
| `SavedDraft_version` | `r_saved_draft_version` (scalar column) | integer |
| `DraftContent` | `r_draft_content` | base_revision → RevisionId, represented_context → RecordId, operations → DraftContent_operations, rationale → DraftContent_rationale, proposal → DraftContent_proposal |
| `DraftContent_operations` | `r_draft_content_operations` | DomainOperation |
| `DraftContent_rationale` | `r_draft_content_rationale` (scalar column) | string |
| `DraftContent_proposal` | `r_draft_content_proposal` | ProposalRef, DraftContent_proposal_v1 |
| `DraftContent_proposal_v1` | `r_draft_content_proposal_v1` (scalar column) | null |
| `ImportOrigin` | `r_import_origin` | digest → ImportOrigin_digest, source_universe → UniverseId, target_universe → UniverseId, complete → ImportOrigin_complete, omitted_records → ImportOrigin_omitted_records |
| `ImportOrigin_digest` | `r_import_origin_digest` (scalar column) | string |
| `ImportOrigin_complete` | `r_import_origin_complete` (scalar column) | boolean |
| `ImportOrigin_omitted_records` | `r_import_origin_omitted_records` (scalar column) | integer |
| `ImportAdmission` | `r_import_admission` | preview_id → OperationId, digest → ImportAdmission_digest, universe_id → UniverseId, name → ImportAdmission_name, complete → ImportAdmission_complete, omitted_records → ImportAdmission_omitted_records, imported → ImportAdmission_imported |
| `ImportAdmission_digest` | `r_import_admission_digest` (scalar column) | string |
| `ImportAdmission_name` | `r_import_admission_name` (scalar column) | string |
| `ImportAdmission_complete` | `r_import_admission_complete` (scalar column) | boolean |
| `ImportAdmission_omitted_records` | `r_import_admission_omitted_records` (scalar column) | integer |
| `ImportAdmission_imported` | `r_import_admission_imported` (scalar column) | boolean |
| `ImportPreview` | `r_import_preview` | id → OperationId, owner → ImportPreview_owner, source_digest → ImportPreview_source_digest, target → UniverseId, source → UniverseId, name → ImportPreview_name, complete → ImportPreview_complete, omitted_records → ImportPreview_omitted_records, records → ImportPreview_records |
| `ImportPreview_owner` | `r_import_preview_owner` (scalar column) | string |
| `ImportPreview_source_digest` | `r_import_preview_source_digest` (scalar column) | string |
| `ImportPreview_name` | `r_import_preview_name` (scalar column) | string |
| `ImportPreview_complete` | `r_import_preview_complete` (scalar column) | boolean |
| `ImportPreview_omitted_records` | `r_import_preview_omitted_records` (scalar column) | integer |
| `ImportPreview_records` | `r_import_preview_records` (scalar column) | integer |
| `ArchiveManifest` | `r_archive_manifest` | format → ArchiveManifest_format, universe → UniverseId, name → ArchiveManifest_name, complete → ArchiveManifest_complete, omitted_records → ArchiveManifest_omitted_records, includes_history → ArchiveManifest_includes_history, includes_workflow → ArchiveManifest_includes_workflow |
| `ArchiveManifest_format` | `r_archive_manifest_format` (scalar column) | string |
| `ArchiveManifest_name` | `r_archive_manifest_name` (scalar column) | string |
| `ArchiveManifest_complete` | `r_archive_manifest_complete` (scalar column) | boolean |
| `ArchiveManifest_omitted_records` | `r_archive_manifest_omitted_records` (scalar column) | integer |
| `ArchiveManifest_includes_history` | `r_archive_manifest_includes_history` (scalar column) | boolean |
| `ArchiveManifest_includes_workflow` | `r_archive_manifest_includes_workflow` (scalar column) | boolean |
| `SourceValidationBindingV1` | `r_source_validation_binding_v1` | kind → ValidationBindingKind, proposal → ProposalRef, base_frame → Frame, selection → AssessmentSelection, submitted_input → SubmittedInput, assessment_state → AssessmentState, execution_result_digest → SourceValidationBindingV1_execution_result_digest, evaluator_version → SourceValidationBindingV1_evaluator_version |
| `ValidationBindingKind` | `r_validation_binding_kind` (scalar column) | string |
| `SourceValidationBindingV1_execution_result_digest` | `r_source_validation_binding_v1_execution_result_digest` (scalar column) | string |
| `SourceValidationBindingV1_evaluator_version` | `r_source_validation_binding_v1_evaluator_version` (scalar column) | string |
