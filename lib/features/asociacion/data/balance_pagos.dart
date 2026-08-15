import 'parada_detalle_service.dart';

/// Total recaudado (pagado) vs pendiente (pendiente + atrasado) para un
/// mes/año/motivo puntual — la fila mínima del balance detallado.
class BalanceGrupo {
  final int mes;
  final int anio;
  final String motivo;
  final double recaudado;
  final double pendiente;
  final double atrasado;
  final double exonerado;
  final int cantidad;

  BalanceGrupo({
    required this.mes,
    required this.anio,
    required this.motivo,
    required this.recaudado,
    required this.pendiente,
    required this.atrasado,
    required this.exonerado,
    required this.cantidad,
  });

  double get totalGrupo => recaudado + pendiente + atrasado + exonerado;
}

/// Cuánto pagó y cuánto debe (pendiente + atrasado) un conductor
/// puntual, sumado a través de todos los meses/motivos de la parada.
class BalanceConductor {
  final String usuarioId;
  final String nombre;
  final double pagado;
  final double debe;
  final int cantidadPagos;

  BalanceConductor({
    required this.usuarioId,
    required this.nombre,
    required this.pagado,
    required this.debe,
    required this.cantidadPagos,
  });
}

/// Balance completo de una parada: totales generales + desglose por
/// mes/motivo + desglose por conductor. Se arma en el cliente a partir
/// de [ParadaDetalleService.cargarCuotasParaBalance] — el volumen de
/// cuotas de una parada es chico, no hace falta agregarlo en SQL.
class BalancePagosParada {
  final double totalRecaudado;
  final double totalPendiente;
  final double totalAtrasado;
  final double totalExonerado;
  final List<BalanceGrupo> porMesMotivo;
  final List<BalanceConductor> porConductor;

  BalancePagosParada({
    required this.totalRecaudado,
    required this.totalPendiente,
    required this.totalAtrasado,
    required this.totalExonerado,
    required this.porMesMotivo,
    required this.porConductor,
  });

  bool get estaVacio => porMesMotivo.isEmpty;
}

BalancePagosParada calcularBalancePagos(List<CuotaItem> cuotas) {
  final grupos = <String, BalanceGrupo>{};
  final conductores = <String, BalanceConductor>{};
  double totalRecaudado = 0;
  double totalPendiente = 0;
  double totalAtrasado = 0;
  double totalExonerado = 0;

  for (final cuota in cuotas) {
    final claveGrupo = '${cuota.anio}-${cuota.mes}-${cuota.motivo}';
    final actual = grupos[claveGrupo] ??
        BalanceGrupo(
          mes: cuota.mes,
          anio: cuota.anio,
          motivo: cuota.motivo,
          recaudado: 0,
          pendiente: 0,
          atrasado: 0,
          exonerado: 0,
          cantidad: 0,
        );
    double recaudado = actual.recaudado;
    double pendiente = actual.pendiente;
    double atrasado = actual.atrasado;
    double exonerado = actual.exonerado;
    switch (cuota.estado) {
      case 'pagado':
        recaudado += cuota.montoTotal;
        totalRecaudado += cuota.montoTotal;
        break;
      case 'atrasado':
        atrasado += cuota.montoTotal;
        totalAtrasado += cuota.montoTotal;
        break;
      case 'exonerado':
        exonerado += cuota.montoTotal;
        totalExonerado += cuota.montoTotal;
        break;
      case 'pendiente':
      default:
        pendiente += cuota.montoTotal;
        totalPendiente += cuota.montoTotal;
    }
    grupos[claveGrupo] = BalanceGrupo(
      mes: cuota.mes,
      anio: cuota.anio,
      motivo: cuota.motivo,
      recaudado: recaudado,
      pendiente: pendiente,
      atrasado: atrasado,
      exonerado: exonerado,
      cantidad: actual.cantidad + 1,
    );

    final conductorActual = conductores[cuota.usuarioId] ??
        BalanceConductor(
          usuarioId: cuota.usuarioId,
          nombre: cuota.usuarioNombre,
          pagado: 0,
          debe: 0,
          cantidadPagos: 0,
        );
    final debeSuma = cuota.estado == 'pendiente' || cuota.estado == 'atrasado' ? cuota.montoTotal : 0;
    final pagadoSuma = cuota.estado == 'pagado' ? cuota.montoTotal : 0;
    conductores[cuota.usuarioId] = BalanceConductor(
      usuarioId: cuota.usuarioId,
      nombre: cuota.usuarioNombre,
      pagado: conductorActual.pagado + pagadoSuma,
      debe: conductorActual.debe + debeSuma,
      cantidadPagos: conductorActual.cantidadPagos + 1,
    );
  }

  final listaGrupos = grupos.values.toList()
    ..sort((a, b) {
      final porAnio = b.anio.compareTo(a.anio);
      if (porAnio != 0) return porAnio;
      final porMes = b.mes.compareTo(a.mes);
      if (porMes != 0) return porMes;
      return a.motivo.compareTo(b.motivo);
    });

  final listaConductores = conductores.values.toList()
    ..sort((a, b) {
      final porDeuda = b.debe.compareTo(a.debe);
      if (porDeuda != 0) return porDeuda;
      return a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
    });

  return BalancePagosParada(
    totalRecaudado: totalRecaudado,
    totalPendiente: totalPendiente,
    totalAtrasado: totalAtrasado,
    totalExonerado: totalExonerado,
    porMesMotivo: listaGrupos,
    porConductor: listaConductores,
  );
}
