import 'package:flutter/material.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_theme.dart';

/// Primera pantalla que ve cualquier usuario al abrir la app. Marca de
/// TapePy (la plataforma) — nada de una organización en particular
/// todavía, eso viene después de tocar "Ingresar".
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();

  // Entrada escalonada: logo primero, después el texto, después el botón.
  late final _logoOpacity = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
  );
  late final _logoScale = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.0, 0.6, curve: Curves.easeOutBack),
  );
  late final _wordmarkAnim = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.35, 0.75, curve: Curves.easeOut),
  );
  late final _taglineAnim = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.5, 0.9, curve: Curves.easeOut),
  );
  late final _buttonAnim = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.65, 1.0, curve: Curves.easeOut),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            children: [
              const Spacer(flex: 3),
              FadeTransition(
                opacity: _logoOpacity,
                child: ScaleTransition(
                  scale: Tween(begin: 0.85, end: 1.0).animate(_logoScale),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.asset(
                      'assets/images/tapepy_logo_rojo.png',
                      width: 160,
                      height: 160,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              _FadeSlideIn(
                animation: _wordmarkAnim,
                child: RichText(
                  text: const TextSpan(
                    style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      height: 1,
                    ),
                    children: [
                      TextSpan(
                          text: 'Tape',
                          style: TextStyle(color: Colors.black87)),
                      TextSpan(
                        text: 'Py',
                        style: TextStyle(color: AppTheme.rojoInstitucional),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _FadeSlideIn(
                animation: _taglineAnim,
                child: Text(
                  'CONTROL · TRANSPORTE · CONFIANZA',
                  style: TextStyle(
                    color: Colors.black.withValues(alpha: 0.55),
                    fontSize: 12,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(flex: 4),
              _FadeSlideIn(
                animation: _buttonAnim,
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      Navigator.of(context)
                          .pushNamed(AppRouter.organizacionSelect);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.rojoInstitucional,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Ingresar',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fade + leve deslizamiento hacia arriba, reutilizado para cada bloque
/// de la entrada escalonada.
class _FadeSlideIn extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;

  const _FadeSlideIn({required this.animation, required this.child});

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.15),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }
}
