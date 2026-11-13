import 'package:flutter_test/flutter_test.dart';
import 'package:buildAhome/models/multi_material_site_proof.dart';

void main() {
  test('session reads measurement unit options from the server', () {
    final s = MultiMaterialSiteProofSession.fromJson({
      'item_run_id': 5,
      'measurement_unit_options': ['Bags', 'SFT', 'RFT', 'SFT'],
      'measurement_unit_default': 'SFT',
      'common': {'measurement_unit': '450 SFT'},
    });
    expect(s.measurementUnitOptions, ['Bags', 'SFT', 'RFT']);
    expect(s.measurementUnitDefault, 'SFT');
    expect(s.common.measurementUnit, '450 SFT');
  });

  test('options fall back to common block and survive copyWith', () {
    final s = MultiMaterialSiteProofSession.fromJson({
      'common': {
        'measurement_unit_options': ['CFT', 'CUM'],
        'measurement_unit_default': 'CFT',
      },
    });
    expect(s.measurementUnitOptions, ['CFT', 'CUM']);
    final c = s.copyWith(materials: const []);
    expect(c.measurementUnitOptions, ['CFT', 'CUM']);
    expect(c.measurementUnitDefault, 'CFT');
  });

  test('missing options parse as empty (app falls back to IndentUnits)', () {
    final s = MultiMaterialSiteProofSession.fromJson({'item_run_id': 1});
    expect(s.measurementUnitOptions, isEmpty);
    expect(s.measurementUnitDefault, '');
  });
}
