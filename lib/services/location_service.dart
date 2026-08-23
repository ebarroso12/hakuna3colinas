import 'dart:async';

import 'package:geolocator/geolocator.dart';

import 'supabase_service.dart';

/// Publica a posição do Hakuna logado no Supabase em intervalos regulares
/// enquanto o rastreamento estiver ativo para um Top.
class LocationService {
  LocationService._();

  static final LocationService instance = LocationService._();

  StreamSubscription<Position>? _subscription;
  String? _activeTopId;

  bool get isTracking => _subscription != null;
  String? get activeTopId => _activeTopId;

  /// Permissão concedida E serviço de localização (GPS) ligado no aparelho.
  Future<bool> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) return false;
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  /// True quando o GPS/localização está desligado no aparelho (não é
  /// questão de permissão do app — é o toggle de localização do sistema).
  /// Distinguir isso de permissão negada importa: são duas telas de
  /// configuração diferentes no Android.
  Future<bool> isLocationServiceDisabled() async {
    return !await Geolocator.isLocationServiceEnabled();
  }

  /// True quando a permissão foi negada permanentemente — só dá pra
  /// resolver abrindo as Configurações do app (Geolocator.openAppSettings()).
  Future<bool> isPermissionDeniedForever() async {
    return await Geolocator.checkPermission() == LocationPermission.deniedForever;
  }

  /// Começa a publicar a posição do usuário para o [topId] a cada
  /// atualização significativa de localização (~ a cada 15m de deslocamento).
  ///
  /// [onError] é chamado — e o rastreamento é parado automaticamente — se
  /// o GPS for desligado, a permissão for revogada ou a sessão expirar
  /// DEPOIS que o rastreamento já começou. Esses erros chegam de forma
  /// assíncrona pelo stream do GPS e não são capturáveis pelo try/catch de
  /// quem chamou startTracking().
  Future<void> startTracking(String topId, {void Function(Object error)? onError}) async {
    if (_subscription != null && _activeTopId == topId) return;
    await stopTracking();

    final hasPermission = await ensurePermission();
    if (!hasPermission) {
      throw StateError('Permissão de localização negada ou GPS desligado');
    }

    _activeTopId = topId;
    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 15,
    );
    _subscription = Geolocator.getPositionStream(locationSettings: settings).listen(
      (position) {
        SupabaseService.instance
            .publishPosition(topId: topId, latitude: position.latitude, longitude: position.longitude)
            .catchError((Object e) {
          final cb = onError;
          stopTracking();
          cb?.call(e);
        });
      },
      onError: (Object error) {
        final cb = onError;
        stopTracking();
        cb?.call(error);
      },
      cancelOnError: true,
    );
  }

  Future<void> stopTracking() async {
    await _subscription?.cancel();
    _subscription = null;
    _activeTopId = null;
  }
}
