import 'package:flutter/material.dart';

import '../app_theme.dart';

/// Stable dark AppBar colors keyed by role name.
/// Same role always resolves to the same color.
class RoleAppBarColor {
  RoleAppBarColor._();

  static const Map<String, Color> _byRole = {
    'QS Head': Color(0xFF1A3A4A),
    'QS Info': Color(0xFF1E4554),
    'QS Engineer': Color(0xFF234F58),
    'Purchase Head': Color(0xFF3D2C1E),
    'Assistant Purchase Manager': Color(0xFF4A3524),
    'Purchase Executive': Color(0xFF3A2E1F),
    'Project Head': Color(0xFF1B254B),
    'Project Coordinator': Color(0xFF1E2A5A),
    'Project Manager': Color(0xFF222F5C),
    'Design Head': Color(0xFF2D1B4E),
    'Senior Architect': Color(0xFF35225A),
    'Architect': Color(0xFF3A2860),
    'Structural Head': Color(0xFF1A3C32),
    'Structural Designer': Color(0xFF1F4538),
    'Junior Site Inspect': Color(0xFF2C3E2D),
    'Soil Engineer': Color(0xFF314232),
    'MEP Head': Color(0xFF1A3550),
    'Electrical Designer': Color(0xFF1F3F5C),
    'MEP Designer': Color(0xFF24455F),
    'PHE Designer': Color(0xFF284B62),
    'MEP Engineer': Color(0xFF2C5165),
    'Site Engineer': Color(0xFF2E4034),
    'Sales Head': Color(0xFF4A1F2E),
    'Sales Manager': Color(0xFF522436),
    'Sales Executive': Color(0xFF5A2A3E),
    'Billing': Color(0xFF1F2E3D),
    'Finance': Color(0xFF1A2F3A),
    'Planning': Color(0xFF2A2640),
    'Planning Engineer': Color(0xFF322C48),
    'Purchase Info': Color(0xFF403528),
    'Client': Color(0xFF1B254B),
    'Technical Info': Color(0xFF253044),
    'QC': Color(0xFF3A1F1F),
    'QA/QC': Color(0xFF422424),
    'Safety': Color(0xFF3D2A14),
    'Socal': Color(0xFF2A3040),
    'Material management': Color(0xFF2F2A22),
    'Assistant project coordinator': Color(0xFF243056),
    'Admin view': Color(0xFF151D3A),
    'Custom': Color(0xFF2C2C2C),
    'QS Interiors': Color(0xFF1A4548),
    'QS & Contracts (QS Engineer)': Color(0xFF1E4D55),
    'Costing Engineer': Color(0xFF254850),
    'Admin': Color(0xFF151D3A),
  };

  /// Fallback dark palette for unlisted roles (hash-stable).
  static const List<Color> _fallbackPalette = [
    Color(0xFF1B254B),
    Color(0xFF1A3A4A),
    Color(0xFF2D1B4E),
    Color(0xFF1A3C32),
    Color(0xFF3D2C1E),
    Color(0xFF4A1F2E),
    Color(0xFF1F2E3D),
    Color(0xFF2A2640),
    Color(0xFF3A1F1F),
    Color(0xFF253044),
    Color(0xFF2F2A22),
    Color(0xFF1A4548),
  ];

  static Color forRole(String? role) {
    final key = (role ?? '').trim();
    if (key.isEmpty) return AppTheme.primaryColorConst;
    final mapped = _byRole[key];
    if (mapped != null) return mapped;
    return _fallbackPalette[key.hashCode.abs() % _fallbackPalette.length];
  }

  /// Slightly lighter companion for gradients (still dark).
  static Color companionFor(Color base) {
    final hsl = HSLColor.fromColor(base);
    return hsl
        .withLightness((hsl.lightness + 0.08).clamp(0.0, 0.45))
        .toColor();
  }
}
