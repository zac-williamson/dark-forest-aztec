"""Guard the generated transport against field loss and stale-width coverage."""
import importlib.util
import json
from pathlib import Path
import re
import tempfile
import unittest
import check

SPEC = importlib.util.spec_from_file_location('field_buffer', Path(__file__).with_name('generate-field-buffer.py'))
BUFFER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUFFER)
HERE = Path(__file__).parent


class FieldBufferTests(unittest.TestCase):
    def test_selected_decoder_calls_original_reader_once_per_word_in_order(self):
        selected = set(json.loads((HERE/'generated/field-buffer-selection.json').read_text())['unrolled'])
        source = BUFFER.render(selected | {4,144,185,245,397}, selected)
        implementations = re.findall(r'impl Deserialize for FieldBuffer<(\d+)> \{(.*?)\n\}', source, re.S)
        self.assertEqual({int(width) for width, _ in implementations}, selected | {4,144,185,245,397})
        for width, body in implementations:
            width = int(width)
            if width in selected:
                expression = re.search(r'Self \{ words: \[(.*?)\] \}', body)[1]
                self.assertEqual(expression.split(', '), ['reader.read()'] * width)
                self.assertNotIn('for ', body)
                self.assertNotIn('read_array', body)
            else:
                self.assertIn(f'<[Field; {width}] as Deserialize>::stream_deserialize(reader)', body)
            self.assertIn(f'fn deserialize(fields: [Field; {width}]) -> Self {{ Self {{ words: fields }} }}', body)
        self.assertTrue(source.startswith(BUFFER.PREFIX))

    def test_every_selected_width_has_executable_boundary_tests(self):
        manifest = json.loads((HERE/'generated/field-buffer-selection.json').read_text())
        source = check.clean((HERE/'field-buffer-tests/src/lib.nr').read_text())
        self.assertIn('use libs::field_buffer::FieldBuffer;', source)
        tests = {}
        for match in re.finditer(r'\bfn\s+(\w+)\s*\(\s*\)\s*\{', source):
            opening = match.end()-1
            closing = check.balanced(source, opening, '{', '}')
            tests[match[1]] = ([re.sub(r'\s+', '', value) for value in check.attributes(source, match.start())],
                              re.sub(r'\s+', '', source[opening+1:closing]))
        # Include the large ordinary decoder as a regression control even when
        # it is not selected for unrolling. The manifest drives all other widths.
        for width in set(manifest['unrolled']) | {185,397}:
            with self.subTest(width=width):
                attributes, body = tests[f'reader_writer_cursor_{width}']
                self.assertIn('test', attributes)
                self.assertNotIn('test(should_fail)', attributes)
                self.assertIn(f'original:[Field;{width}]', body)
                self.assertIn(f'foriin0..{width}', body)
                self.assertIn('{-1}', body)
                self.assertIn('i as Field+0x100000000000000000000000000000000000000000000000000'.replace(' ', ''), body)
                for expression in [
                    'writer.write(17)', 'writer.write(29)',
                    'FieldBuffer{words:original}.stream_serialize(&mutwriter)',
                    'Reader::new(writer.finish())', 'assert_eq(reader.read(),17)',
                    f'recovered:FieldBuffer<{width}>=Deserialize::stream_deserialize(&mutreader)',
                    'assert_eq(recovered.words,original)', 'assert_eq(reader.read(),29)', 'reader.finish()',
                    f'assert_eq(FieldBuffer::<{width}>::deserialize(original).serialize(),original)',
                ]:
                    self.assertIn(expression, body)
                attributes, body = tests[f'insufficient_reader_{width}']
                self.assertIn('test(should_fail)', attributes)
                self.assertIn(f'Reader::new([0;{width-1}])', body)
                self.assertIn(f'FieldBuffer<{width}>=Deserialize::stream_deserialize(&mutreader)', body)

    def test_width_inventory_ignores_old_generated_implementations_and_build_outputs(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root/'libs/src').mkdir(parents=True)
            (root/'libs/src/field_buffer.nr').write_text('impl Deserialize for FieldBuffer<999> {}')
            (root/'target').mkdir()
            (root/'target/generated.nr').write_text('FieldBuffer<123>')
            (root/'consumer.nr').write_text('fn a(x: FieldBuffer<56>) {} fn b(x: FieldBuffer::<88>) {}')
            self.assertEqual(BUFFER.used_widths(root), {4,56,88})

    def test_missing_selected_width_cannot_silently_fall_back(self):
        with self.assertRaises(AssertionError):
            BUFFER.render({4,56}, {56,88})


if __name__ == '__main__':
    unittest.main()
