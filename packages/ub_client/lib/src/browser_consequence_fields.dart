import 'dart:js_interop';

import 'package:ub_domain/ub_domain.dart';

import 'browser_input_fields.dart';

// Only consequence/effect order is numeric on these wire records. Retain exact
// decimal text in the named order field rather than converting it to a JS number.
CanonicalObject _enteredOrder(CanonicalObject value) => CanonicalObject([
  for (final field in value.fields)
    field.key == 'order'
        ? MapEntry(
            'order',
            CanonicalString((field.value as CanonicalNumber).digits),
          )
        : field,
]);
CanonicalObject _wireOrder(CanonicalValue value) => CanonicalObject([
  for (final field in (value as CanonicalObject).fields)
    field.key == 'order'
        ? MapEntry(
            'order',
            CanonicalNumber((field.value as CanonicalString).value),
          )
        : field,
]);
JSAny encodeBrowserEffectSlot(EffectSlot value) =>
    encodeBrowserInput(_enteredOrder(value.toWire()))!;
EffectSlot decodeBrowserEffectSlot(JSAny value) =>
    EffectSlot.fromWire(_wireOrder(decodeBrowserInput(value)));
JSAny encodeBrowserEntityEffect(EntityEffect value) =>
    encodeBrowserInput(_enteredOrder(value.toWire()))!;
EntityEffect decodeBrowserEntityEffect(JSAny value) =>
    EntityEffect.fromWire(_wireOrder(decodeBrowserInput(value)));

JSAny encodeBrowserAction(ActionDefinitionRecord value) => encodeBrowserInput(
  CanonicalObject([
    ...value.toWire().fields.where((f) => f.key != 'consequenceContract'),
    if (value.consequenceContract != null)
      MapEntry(
        'consequenceContract',
        CanonicalObject([
          MapEntry('kind', CanonicalString('action_consequences')),
          MapEntry(
            'slots',
            CanonicalArray(
              value.consequenceContract!.slots.map(
                (s) => _enteredOrder(s.toWire()),
              ),
            ),
          ),
        ]),
      ),
  ]),
)!;
ActionDefinitionRecord decodeBrowserAction(JSAny value) {
  final fields = (decodeBrowserInput(value) as CanonicalObject).fields;
  return ActionDefinitionRecord.fromWire(
    CanonicalObject([
      for (final field in fields)
        if (field.key == 'consequenceContract')
          MapEntry(
            field.key,
            CanonicalObject([
              for (final contractField
                  in (field.value as CanonicalObject).fields)
                contractField.key == 'slots'
                    ? MapEntry(
                        'slots',
                        CanonicalArray(
                          (contractField.value as CanonicalArray).items.map(
                            _wireOrder,
                          ),
                        ),
                      )
                    : contractField,
            ]),
          )
        else
          field,
    ]),
  );
}

JSAny encodeBrowserEvent(EventRecord value) => encodeBrowserInput(
  CanonicalObject([
    ...value.toWire().fields.where((f) => f.key != 'effects'),
    MapEntry(
      'effects',
      CanonicalArray(value.effects.map((e) => _enteredOrder(e.toWire()))),
    ),
  ]),
)!;
EventRecord decodeBrowserEvent(JSAny value) => EventRecord.fromWire(
  CanonicalObject([
    for (final field in (decodeBrowserInput(value) as CanonicalObject).fields)
      field.key == 'effects'
          ? MapEntry(
              'effects',
              CanonicalArray(
                (field.value as CanonicalArray).items.map(_wireOrder),
              ),
            )
          : field,
  ]),
);
