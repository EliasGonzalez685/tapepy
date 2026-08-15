import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

enum ParadaEstado { ok, atencion, urgente }

extension ParadaEstadoUi on ParadaEstado {
  Color get color {
    switch (this) {
      case ParadaEstado.ok:
        return AppTheme.estadoOk;
      case ParadaEstado.atencion:
        return AppTheme.estadoAtencion;
      case ParadaEstado.urgente:
        return AppTheme.estadoUrgente;
    }
  }

  String get etiqueta {
    switch (this) {
      case ParadaEstado.ok:
        return 'OK';
      case ParadaEstado.atencion:
        return 'Atención';
      case ParadaEstado.urgente:
        return 'Urgente';
    }
  }
}

class ParadaResumen {
  final String id;
  final String nombre;
  final int conductoresCount;
  final int cuotasAtrasadasCount;
  final int docsPorVencerCount;
  // Cuántos de los conductores de esta parada tienen la bandera "en
  // servicio" prendida ahora mismo. No viene de la vista `parada_resumen`
  // (que es solo de Postgres) — se calcula aparte en
  // AsociacionDashboardService y se mezcla acá con copyWith. Por eso
  // arranca en 0 por defecto: cualquier código que solo llame a
  // ParadaResumen.fromMap (como parada_presidente_service.dart) sigue
  // andando igual, sin este dato.
  final int conductoresActivosCount;

  ParadaResumen({
    required this.id,
    required this.nombre,
    required this.conductoresCount,
    required this.cuotasAtrasadasCount,
    required this.docsPorVencerCount,
    this.conductoresActivosCount = 0,
  });

  ParadaEstado get estado {
    if (cuotasAtrasadasCount > 0) return ParadaEstado.urgente;
    if (docsPorVencerCount > 0) return ParadaEstado.atencion;
    return ParadaEstado.ok;
  }

  String get subtitulo {
    final activos = '$conductoresActivosCount/$conductoresCount activos';
    if (cuotasAtrasadasCount > 0) {
      return '$activos · $cuotasAtrasadasCount atrasados';
    }
    if (docsPorVencerCount > 0) {
      return '$activos · $docsPorVencerCount docs vencen';
    }
    return '$activos · Todo en regla';
  }

  ParadaResumen copyWith({int? conductoresActivosCount}) {
    return ParadaResumen(
      id: id,
      nombre: nombre,
      conductoresCount: conductoresCount,
      cuotasAtrasadasCount: cuotasAtrasadasCount,
      docsPorVencerCount: docsPorVencerCount,
      conductoresActivosCount: conductoresActivosCount ?? this.conductoresActivosCount,
    );
  }

  factory ParadaResumen.fromMap(Map<String, dynamic> map) {
    return ParadaResumen(
      id: map['id'] as String,
      nombre: map['nombre'] as String,
      conductoresCount: (map['conductores_count'] as num?)?.toInt() ?? 0,
      cuotasAtrasadasCount:
          (map['cuotas_atrasadas_count'] as num?)?.toInt() ?? 0,
      docsPorVencerCount: (map['docs_por_vencer_count'] as num?)?.toInt() ?? 0,
    );
  }
}
