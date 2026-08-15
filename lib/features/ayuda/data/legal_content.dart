/// Contenido de la Política de Privacidad y los Términos de Uso,
/// embebido para mostrarlo dentro de la app (pantalla "Condiciones y
/// Políticas de Privacidad" del menú "Ayuda y comentarios"). Es el mismo
/// texto que los documentos Word en docs/legal/ — si se edita uno,
/// conviene reflejar el cambio en el otro.
class SeccionLegal {
  final String titulo;
  final List<String> parrafos;
  const SeccionLegal(this.titulo, this.parrafos);
}

const String legalVersion = 'Versión 1.0 — vigente desde el 15 de agosto de 2026';

const List<SeccionLegal> terminosDeUso = [
  SeccionLegal('Descripción del servicio', [
    'TapePy es una plataforma de gestión para asociaciones de transporte que permite registrar socios y sus vehículos, cargar y verificar documentación, generar carnets digitales y constancias, administrar el cobro de cuotas, comunicarse internamente y generar listados oficiales.',
    'TapePy provee la tecnología. Cada organización es responsable de cómo la usa: qué información exige a sus socios, qué decisiones administrativas toma y qué validez le da a los documentos generados dentro de la app frente a terceros.',
  ]),
  SeccionLegal('Quién puede usar la app', [
    'TapePy está destinada a personas mayores de edad que sean socios de una organización afiliada a la plataforma (conductores) o que ejerzan un cargo de representación dentro de ella (presidente de parada o de asociación). El alta de nuevos socios queda sujeta a la aprobación del presidente correspondiente.',
  ]),
  SeccionLegal('Tu cuenta y tu responsabilidad', [
    'Sos responsable de mantener tu contraseña en secreto y de todo lo que ocurra en tu cuenta.',
    'Cada conductor carga y es responsable de sus propios documentos personales y de su vehículo: la app no verifica automáticamente su autenticidad ni su vigencia real, solo organiza lo que vos cargás.',
    'Te comprometés a cargar información veraz y a mantener actualizada tu documentación, en especial las fechas de vencimiento.',
    'Los presidentes de parada y de asociación acceden a datos de otros socios únicamente en el ejercicio de su cargo.',
  ]),
  SeccionLegal('Uso aceptable', [
    'Al usar TapePy, te comprometés a no cargar documentación falsa o de otra persona sin autorización, no usar la información de otros socios para fines ajenos a la gestión de la asociación, no intentar vulnerar la seguridad del sistema y no usar la mensajería interna para fines ajenos a la actividad de la asociación.',
  ]),
  SeccionLegal('Documentos, carnets, constancias y listados generados', [
    'TapePy facilita la generación y organización de estos documentos, pero no garantiza por sí sola su validez legal ante autoridades de tránsito, municipales u otras — esa validez depende del cumplimiento de la normativa aplicable, que es responsabilidad de cada organización y de cada socio.',
  ]),
  SeccionLegal('Firma digital dentro de la app', [
    'El mecanismo de firma digital de TapePy es un sistema interno de autorización entre los presidentes y sus socios. No constituye, por sí mismo, una firma electrónica certificada en los términos de la Ley N° 4017/2010 de Validez Jurídica de la Firma Electrónica, salvo que se indique expresamente lo contrario.',
  ]),
  SeccionLegal('Cuotas y pagos', [
    'La gestión de cuotas dentro de TapePy es manual: los presidentes registran los pagos y los conductores pueden reportar un pago adjuntando un comprobante. TapePy no procesa pagos automáticamente ni almacena datos de tarjetas o cuentas bancarias.',
  ]),
  SeccionLegal('Propiedad intelectual', [
    'TapePy, su nombre, diseño y funcionamiento son propiedad de su equipo desarrollador. Los datos y contenidos que cada organización y sus socios cargan en la app siguen siendo de su propiedad.',
  ]),
  SeccionLegal('Suspensión y baja de cuentas', [
    'Una cuenta nueva queda pendiente de aprobación hasta que el presidente correspondiente la confirme. El presidente de asociación puede dar de baja a un conductor cuando corresponda. Cualquier usuario puede solicitar la baja de su propia cuenta.',
  ]),
  SeccionLegal('Disponibilidad y límites de responsabilidad', [
    'TapePy es una herramienta de gestión y no reemplaza el asesoramiento legal, contable o de tránsito que tu asociación pueda necesitar. No garantizamos disponibilidad ininterrumpida del servicio.',
  ]),
  SeccionLegal('Ley aplicable', [
    'Estos términos se rigen por las leyes de la República del Paraguay.',
  ]),
];

const List<SeccionLegal> politicaDePrivacidad = [
  SeccionLegal('Quién es responsable de tus datos', [
    'Tu organización (por ejemplo, Traude) es la Responsable del Tratamiento: decide para qué se usan tus datos dentro de la asociación y es tu primer punto de contacto.',
    'TapePy actúa como Encargado del Tratamiento: provee la tecnología y sigue las instrucciones de cada organización — no usa tus datos para fines propios, comerciales ni publicitarios.',
    'Contacto para consultas de privacidad: eliasgonzalez685@gmail.com.',
  ]),
  SeccionLegal('Marco legal', [
    'Esta política se elabora conforme a la Constitución Nacional, la Ley N° 7593/2025 "De Protección de Datos Personales" (cuyos principios TapePy adopta de forma proactiva) y la Ley N° 4868/2013 de Comercio Electrónico.',
  ]),
  SeccionLegal('Qué datos recolectamos', [
    'Datos de identificación (nombre, cédula, teléfono, correo, contraseña cifrada), foto de perfil y carnet digital.',
    'Datos del o los vehículos (marca, modelo, chapa, resolución, fotos).',
    'Documentos personales y del vehículo (cédula, licencia, seguro, revisión técnica y similares, incluyendo cualquier documento adicional que cargues con su descripción).',
    'Firma digital de los presidentes, usada solo para autorizar listados y constancias.',
    'Datos de cuotas y pagos (monto, estado, método declarado y comprobante si corresponde).',
    'Mensajes internos, incidentes reportados y convenios de la asociación.',
    'No recolectamos tu ubicación en tiempo real ni datos de navegación fuera de la app.',
  ]),
  SeccionLegal('Para qué usamos tus datos', [
    'Gestionar tu identidad y membresía, generar tu carnet y tus constancias, verificar tu documentación, administrar el cobro de cuotas, habilitar la comunicación interna y generar los listados oficiales de la asociación. Nunca con fines de marketing o publicidad de terceros.',
  ]),
  SeccionLegal('Con quién se comparten tus datos', [
    'Dentro de tu organización: tu presidente de parada ve a los conductores de esa parada; el presidente de asociación ve a todas las paradas de su organización. Ninguna otra organización puede ver tus datos.',
    'Proveedores tecnológicos: Supabase (base de datos y almacenamiento, con servidores en Brasil — esto implica una transferencia internacional de datos) y Firebase Cloud Messaging de Google (solo para notificaciones push).',
    'No vendemos ni compartimos tus datos con terceros para fines publicitarios.',
  ]),
  SeccionLegal('Seguridad de la información', [
    'Aislamiento total de datos entre organizaciones, control de acceso por rol reforzado en la base de datos, documentos guardados en almacenamiento privado con enlaces temporales, y contraseñas siempre cifradas.',
  ]),
  SeccionLegal('Tus derechos', [
    'Podés pedir en cualquier momento y sin costo: acceso, rectificación, cancelación/supresión, oposición, portabilidad y revocación del consentimiento. Contactá al presidente de tu asociación o a eliasgonzalez685@gmail.com.',
  ]),
  SeccionLegal('Menores de edad', [
    'TapePy está destinada a personas mayores de edad habilitadas para conducir. No está dirigida a menores de edad.',
  ]),
];
