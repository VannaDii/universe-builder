"""Independent Draft 2020-12 validation of generated schemas and examples."""
import copy
import json
from pathlib import Path
from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[1]

def validators():
    result = {}
    for tool in json.loads((ROOT / 'contracts/tools.json').read_text()):
        for key in ('input_schema', 'output_schema'):
            Draft202012Validator.check_schema(tool[key])
        result[tool['name']] = (Draft202012Validator(tool['input_schema']), Draft202012Validator(tool['output_schema']))
    return result

def main():
    schemas = validators()
    examples = json.loads((ROOT / 'contracts/examples.json').read_text())
    assert len(schemas) == len(examples) == 16
    count = 0
    for example in examples:
        validator = schemas[example['tool']][0]
        validator.validate(example['args'])
        for name, value in [('universe', None), ('universe', ''), ('universe', '*'), ('universe_id', 'bad'), ('approved', True), ('world', None)]:
            malformed = copy.deepcopy(example['args'])
            malformed[name] = value
            assert not validator.is_valid(malformed), (example['tool'], malformed)
            count += 1
        malformed = copy.deepcopy(example['args'])
        del malformed['universe']
        assert not validator.is_valid(malformed)
        count += 1
    # Query event-side pairing must not make event-effect record inputs
    # impossible: those records have event/slot, with no event_side member.
    event = {'record': 'rec_000000000000000000000001'}
    for name in ('universe_validate', 'universe_propose'):
        root = schemas[name][0].schema
        for model, value in (
            ('EventEffectRef', {'event': event, 'slot': 'stock'}),
            ('EvidenceBasis', {'kind': 'event_effect', 'event': event, 'slot': 'stock'}),
        ):
            validator = Draft202012Validator({'$defs': root['$defs'], **root['$defs'][model]})
            validator.validate(value)
            assert not validator.is_valid({**value, 'event_side': 'entry'})
    print(f'PASS: {2 * len(schemas)} schemas, {len(examples)} valid examples, {count} invalid examples')

if __name__ == '__main__':
    main()
