import 'package:flutter/material.dart';

/// Paleta Dinna, a mesma usada nos artefatos das Atividades 1 e 2.
abstract final class DinnaColors {
  static const cream = Color(0xFFFBF6F0);
  static const terracotta = Color(0xFFB4532A);
  static const terracottaSoft = Color(0xFFF4E3D7);
  static const brown = Color(0xFF2A211C);
  static const muted = Color(0xFF6F625A);
  static const sage = Color(0xFF5E7355);
  static const sageSoft = Color(0xFFE6ECE1);
  static const amber = Color(0xFFA86B12);
  static const amberSoft = Color(0xFFF6EAD2);
  static const line = Color(0xFFE6DAD0);
  static const error = Color(0xFFA63A2B);
  static const white = Color(0xFFFFFFFF);

  /// Degradês do Figma para produto sem foto, do tom claro ao escuro.
  static const productPlaceholders = <(Color, Color)>[
    (Color(0xFFE07A45), Color(0xFFB4532A)),
    (Color(0xFFD8B27E), Color(0xFFA9844F)),
    (Color(0xFF6B5D55), Color(0xFF3F332D)),
    (Color(0xFFEC9A84), Color(0xFFCB644E)),
    (Color(0xFFE2655A), Color(0xFFAE3A31)),
    (Color(0xFFF0CD74), Color(0xFFD6A13E)),
    (Color(0xFF94B07F), Color(0xFF5E7355)),
  ];
}
