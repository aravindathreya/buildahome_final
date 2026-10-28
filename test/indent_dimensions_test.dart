import 'package:flutter_test/flutter_test.dart';
import 'package:buildAhome/services/indent_dimensions.dart';

void main() {
  test('parse dimensions', () {
    final d = IndentDimensions.parse({
      'dimensions': [
        {'label': '8mm Dia TMT Bar', 'short_label': '08mm Dia'},
        {'label': '10mm Dia TMT Bar'},
        {'label': ''},
      ]
    });
    expect(d.length, 2);
    expect(d[0].shortLabel, '08mm Dia');
    expect(d[1].shortLabel, '10mm Dia TMT Bar');
    expect(IndentDimensions.parse({'x': 1}), isEmpty);
    expect(IndentDimensions.parse(null), isEmpty);
  });

  test('total and breakdown', () {
    expect(IndentDimensions.total(['100', '50.5', '', 'abc', '-3']), 150.5);
    expect(IndentDimensions.formatNumber(150.0), '150');
    expect(IndentDimensions.formatNumber(150.5), '150.5');
    expect(
      IndentDimensions.breakdown(
          ['8mm Dia TMT Bar', '10mm Dia TMT Bar'], ['100', '50'], 'Kg'),
      '8mm Dia TMT Bar: 100 Kg; 10mm Dia TMT Bar: 50 Kg',
    );
  });
}
