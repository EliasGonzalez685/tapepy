import 'package:flutter/material.dart';

/// Home del rol superadmin: logs del sistema, no editable por la
/// asociación (separación de permisos definida en el modelo de datos).
class SuperadminHomeScreen extends StatelessWidget {
  const SuperadminHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Home Superadmin (placeholder)')),
    );
  }
}
