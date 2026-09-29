import 'package:flutter_test/flutter_test.dart';
import 'package:buildAhome/site_proof_multi/multi_material_site_proof_flow.dart';

void main() {
  group('shouldUseMultiMaterialSiteProof', () {
    test('defaults to multi for empty / multi / any count', () {
      expect(shouldUseMultiMaterialSiteProof(), isTrue);
      expect(shouldUseMultiMaterialSiteProof(siteProofFlow: 'multi'), isTrue);
      expect(shouldUseMultiMaterialSiteProof(materialCount: 1), isTrue);
      expect(shouldUseMultiMaterialSiteProof(materialCount: 5), isTrue);
    });

    test('only explicit single keeps legacy path', () {
      expect(shouldUseMultiMaterialSiteProof(siteProofFlow: 'single'), isFalse);
      expect(
        shouldUseMultiMaterialSiteProof(siteProofFlow: 'single', materialCount: 3),
        isFalse,
      );
    });
  });
}
