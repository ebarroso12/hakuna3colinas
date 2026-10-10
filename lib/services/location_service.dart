import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../offline/outbox.dart';
import '../offline/sync_service.dart';
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
    return await Geolocator.checkPermission() ==
        LocationPermission.deniedForever;
  }

  /// True quando o usuário escolheu "Permitir o tempo todo".
  ///
  /// O rastreamento funciona sem isso — o serviço de primeiro plano (a
  /// notificação fixa) segura o GPS vivo com a tela bloqueada. Esta
  /// permissão é a camada extra: sem ela, se o Android matar o serviço por
  /// pressão de memória ou economia de bateria agressiva (comum em Xiaomi,
  /// Samsung e Motorola), a trilha fica com buraco até o Hakuna reabrir o
  /// app.
  ///
  /// O Android **não** concede isso no diálogo normal: o usuário precisa
  /// escolher na tela de Configurações do app. Use
  /// [openSettingsForBackground] para levá-lo até lá.
  Future<bool> hasBackgroundPermission() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
    return await Geolocator.checkPermission() == LocationPermission.always;
  }

  /// Abre as Configurações do app para o usuário marcar "Permitir o tempo
  /// todo". Chame só depois de explicar por que isso importa — pedir sem
  /// contexto é o caminho mais rápido para o usuário negar.
  Future<void> openSettingsForBackground() => Geolocator.openAppSettings();

  /// No Android, usa um serviço de primeiro plano com notificação fixa.
  /// É isso que impede o sistema de cortar as atualizações quando o app sai
  /// da frente: sem o serviço, o Android para de entregar posições poucos
  /// minutos depois de a tela bloquear.
  LocationSettings _locationSettings() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: _distanceFilterMeters,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Legendários Connect',
          notificationText: 'Rastreando sua posição neste Top',
          notificationChannelName: 'Rastreamento de posição',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: _distanceFilterMeters,
    );
  }

  /// Nome da entidade na fila offline.
  static const entityPosicao = 'hakuna_positions';

  /// Liga o envio das posições da fila. Chamar uma vez, na subida do app.
  void registrarUploader() {
    SyncService.instance.registerUploader(entityPosicao, (entrada) async {
      await SupabaseService.instance.publishPosition(
        topId: entrada.payload['top_id'] as String,
        latitude: (entrada.payload['latitude'] as num).toDouble(),
        longitude: (entrada.payload['longitude'] as num).toDouble(),
        recordedAt: entrada.payload['recorded_at'] as String?,
      );
    });
  }

  /// Quantos pontos ainda não subiram — a tela mostra pro Hakuna saber que
  /// a trilha está guardada, mesmo sem sinal.
  Future<int> pontosPendentes() =>
      Outbox.instance.pendingCount(entity: entityPosicao);

  /// Publica uma posição nova a cada 15 m de deslocamento. Esse filtro é o
  /// que segura o ruído de GPS fora da conta de distância do StatsService.
  static const int _distanceFilterMeters = 15;

  /// Começa a publicar a posição do usuário para o [topId] a cada
  /// atualização significativa de localização (~ a cada 15m de deslocamento).
  ///
  /// [onError] é chamado — e o rastreamento é parado automaticamente — se
  /// o GPS for desligado, a permissão for revogada ou a sessão expirar
  /// DEPOIS que o rastreamento já começou. Esses erros chegam de forma
  /// assíncrona pelo stream do GPS e não são capturáveis pelo try/catch de
  /// quem chamou startTracking().
  Future<void> startTracking(
    String topId, {
    void Function(Object error)? onError,
  }) async {
    if (_subscription != null && _activeTopId == topId) return;
    await stopTracking();

    final hasPermission = await ensurePermission();
    if (!hasPermission) {
      throw StateError('Permissão de localização negada ou GPS desligado');
    }

    _activeTopId = topId;
    _subscription =
        Geolocator.getPositionStream(locationSettings: _locationSettings())
            .listen(
              (position) {
                // Vai pra FILA LOCAL, nunca direto pro Supabase.
                //
                // Antes isso publicava na rede a cada ponto, e qualquer
                // falha de conexao parava o rastreamento inteiro — numa
                // trilha, a primeira area sem sinal matava a trilha toda.
                // Agora o ponto fica no celular e sobe quando der.
                unawaited(
                  Outbox.instance
                      .enqueue(
                        entity: entityPosicao,
                        payload: {
                          'top_id': topId,
                          'latitude': position.latitude,
                          'longitude': position.longitude,
                          'recorded_at': position.timestamp
                              .toUtc()
                              .toIso8601String(),
                        },
                        topId: topId,
                      )
                      .catchError((Object e) {
                        // Falha ao GRAVAR no proprio celular e grave: sem
                        // isso o ponto se perde de verdade.
                        final cb = onError;
                        stopTracking();
                        cb?.call(e);
                        return '';
                      }),
                );
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
