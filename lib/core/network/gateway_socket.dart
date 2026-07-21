import 'dart:async';

/// Mises à jour « temps réel » depuis la passerelle.
///
/// L'admin-service n'expose PAS de canal WebSocket : on obtient donc le
/// quasi-temps réel par interrogation périodique (polling) de l'API. Cette
/// classe encapsule ce rythme pour que les écrans n'aient qu'un `start`/`stop`.
///
/// Le jour où la passerelle exposera un vrai WebSocket, seule cette classe est
/// à réécrire (les écrans consomment déjà un simple flux d'événements « tick »).
class GatewayLiveUpdates {
  GatewayLiveUpdates({this.interval = const Duration(seconds: 5)});

  final Duration interval;
  Timer? _timer;

  bool get isRunning => _timer?.isActive ?? false;

  /// Démarre le rafraîchissement périodique ; [onTick] est appelé à chaque cycle.
  void start(Future<void> Function() onTick) {
    stop();
    _timer = Timer.periodic(interval, (_) async {
      try {
        await onTick();
      } catch (_) {
        // Un cycle en échec (hors-ligne) ne doit pas arrêter la boucle.
      }
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() => stop();
}
