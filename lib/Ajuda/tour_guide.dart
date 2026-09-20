import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TourGuide {
  static const _kHomeTourDone = 'home_tour_done_v1';

  /// Inicia um tour simples (sem highlight), apenas com balões/diálogos
  /// para cada key. Retorna true se chegou a iniciar de fato.
  static Future<bool> startHomeTourSimple(
    BuildContext context, {
    required List<GlobalKey> keys,
  }) async {
    // ✅ garante retorno em todas as rotas
    if (!context.mounted) return false;
    if (keys.isEmpty) return false;

    try {
      // Mostra um passo por vez
      for (int i = 0; i < keys.length; i++) {
        final key = keys[i];
        // Se a key não está montada, pula o passo
        if (key.currentContext == null) continue;

        final label = _guessWidgetLabel(key.currentContext!);

        final proceed = await showDialog<bool>(
          context: context,
          barrierDismissible: true,
          builder:
              (_) => AlertDialog(
                title: Text('Dica ${i + 1}/${keys.length}'),
                content: Text(
                  label ??
                      'Este componente faz parte do fluxo principal. Explore-o para continuar aprendendo.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Pular tour'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(i == keys.length - 1 ? 'Concluir' : 'Próximo'),
                  ),
                ],
              ),
        );

        // Se o usuário cancelou (null) ou escolheu pular (false), encerra
        if (proceed != true) {
          return true; // o tour chegou a iniciar, então true
        }
      }

      return true; // terminou todos os passos
    } catch (_) {
      // Em caso de erro, não inicia/continua o tour
      return false;
    }
  }

  /// Dispara o tour da Home só 1x (controlado por SharedPreferences)
  static Future<void> maybeStartHomeTourOnce(
    BuildContext context, {
    required List<GlobalKey> steps,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final done = prefs.getBool(_kHomeTourDone) ?? false;
    if (done) return;

    final started = await startHomeTourSimple(context, keys: steps);
    if (started) {
      await prefs.setBool(_kHomeTourDone, true);
    }
  }

  /// Alias para compatibilidade com chamadas antigas.
  static Future<bool> startHomeTour(
    BuildContext context, {
    required List<GlobalKey> steps,
  }) {
    return startHomeTourSimple(context, keys: steps);
  }

  /// Tenta extrair um texto amigável do widget alvo (opcional)
  static String? _guessWidgetLabel(BuildContext ctx) {
    final widget = ctx.widget;
    if (widget is ListTile) {
      final t = widget.title;
      if (t is Text) return t.data;
    }
    // Você pode melhorar isso conforme seus componentes
    return null;
  }
}
