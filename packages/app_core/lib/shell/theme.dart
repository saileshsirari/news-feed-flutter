import 'package:flutter/material.dart';

/// The super app's look, shared by every mini-app (each tile adds its own
/// colour on the Home grid).
ThemeData appTheme({Brightness brightness = Brightness.light}) => ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: brightness),
);
