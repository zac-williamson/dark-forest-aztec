import unittest
import build

class TouchBindings(unittest.TestCase):
    def rows(self):
        return {'config-Config.json':{'classId':'0x11'},'artifact-ArtifactStorage.json':{'classId':'0x22'},'artifact_location-ArtifactLocationStorage.json':{'classId':'0x33'}}
    def test_initial_config_keeps_touch_disabled(self):
        rows=self.rows();rows.pop('artifact-ArtifactStorage.json');rows.pop('artifact_location-ArtifactLocationStorage.json')
        value=build.config_binding(rows,True)
        self.assertIn('CONFIG_CLASS: Field = 0x11;',value)
        self.assertIn('ARTIFACT_TOUCH_CLASS: Field = 0;',value)
        self.assertIn('LOCATION_TOUCH_CLASS: Field = 0;',value)
    def test_final_config_requires_both_actual_classes(self):
        rows=self.rows();rows.pop('artifact_location-ArtifactLocationStorage.json')
        with self.assertRaisesRegex(ValueError,'Both actual'):build.config_binding(rows)
    def test_actual_facade_ids_fill_both_existing_config_files(self):
        rows={build.filename(e):{'classId':hex(i+1)} for i,e in enumerate(build.ENTRIES)}
        values=build.codegen(rows)
        self.assertEqual(set(values),set(build.BINDINGS))
        self.assertEqual(values[build.BINDINGS[0]],values[build.BINDINGS[1]])
        for symbol,file in [('ARTIFACT_TOUCH_CLASS','artifact-ArtifactStorage.json'),('LOCATION_TOUCH_CLASS','artifact_location-ArtifactLocationStorage.json')]:
            self.assertIn(f"{symbol}: Field = {rows[file]['classId']};",values[build.BINDINGS[0]])

if __name__=='__main__':unittest.main()
