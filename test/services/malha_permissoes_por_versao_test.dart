// A malha não pode exigir permissão que o Android daquele celular NÃO TEM.
//
// Defeito achado em 23/11/2026, lendo o código do `permission_handler` até
// o fim. `MalhaService._pedirPermissoes` pedia `bluetoothScan`,
// `bluetoothAdvertise` e `bluetoothConnect` em toda versão e exigia as três
// concedidas. As três só existem no Android 12 (SDK 31) — e o plugin, ao
// receber um grupo sem nenhuma permissão naquela versão, devolve DENIED:
//
//     if (names == null || names.isEmpty()) { ...
//         requestResults.put(permission, PERMISSION_STATUS_DENIED);
//
// Então em TODO celular Android 11 ou mais antigo a malha se recusava a
// ligar, dizendo que faltava permissão de Bluetooth — num aparelho onde
// `BLUETOOTH` e `BLUETOOTH_ADMIN` são de instalação, já concedidas, e o
// rádio funcionaria. O chat sem rede simplesmente não existia para quem
// tem celular mais antigo, e a tela culpava o usuário.
//
// O código já tratava disso para `nearbyWifiDevices`. O mecanismo é o
// mesmo para as três de Bluetooth, e elas ficaram fora da correção.
//
// Estes testes batem na REGRA, que é pura. O rádio em si não se prova aqui
// — isso exige dois Android em modo avião, e continua pendente.
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:legendario_connect/services/malha_service.dart';

void main() {
  const trio = [
    Permission.bluetoothScan,
    Permission.bluetoothAdvertise,
    Permission.bluetoothConnect,
  ];

  group('Android 11 e anteriores (SDK < 31)', () {
    // 24 é o minSdk do projeto; 30 é o Android 11.
    for (final sdk in [24, 28, 29, 30]) {
      test('SDK $sdk não exige o trio do Bluetooth', () {
        final q = MalhaService.permissoesPara(sdk);
        for (final p in trio) {
          expect(
            q.obrigatorias,
            isNot(contains(p)),
            reason: 'no SDK $sdk esta permissão não existe, e exigi-la '
                'bloqueia a malha num aparelho onde o rádio funciona',
          );
          expect(q.opcionais, isNot(contains(p)));
        }
      });

      test('SDK $sdk ainda exige localização', () {
        // Em toda versão o Android exige localização para buscar por BLE,
        // mesmo sem usar GPS. Sem ela a busca devolve lista vazia e não
        // dá erro — o pior modo de falhar.
        expect(MalhaService.permissoesPara(sdk).obrigatorias, [
          Permission.location,
        ]);
      });
    }
  });

  group('Android 12 (SDK 31 e 32)', () {
    for (final sdk in [31, 32]) {
      test('SDK $sdk exige o trio, porque ali ele existe', () {
        final q = MalhaService.permissoesPara(sdk);
        expect(q.obrigatorias, containsAll(trio));
        expect(q.obrigatorias, contains(Permission.location));
      });

      test('SDK $sdk NÃO pede nearbyWifiDevices', () {
        // Só existe no 33. Pedir antes repete o mesmo defeito, de outro
        // jeito: diálogo que não aparece e status negado de graça.
        final q = MalhaService.permissoesPara(sdk);
        expect(q.obrigatorias, isNot(contains(Permission.nearbyWifiDevices)));
        expect(q.opcionais, isEmpty);
      });
    }
  });

  group('Android 13+ (SDK 33)', () {
    test('pede nearbyWifiDevices, mas NÃO exige', () {
      final q = MalhaService.permissoesPara(33);
      expect(
        q.opcionais,
        contains(Permission.nearbyWifiDevices),
        reason: 'é o transporte por WiFi, que acelera depois do BLE',
      );
      expect(
        q.obrigatorias,
        isNot(contains(Permission.nearbyWifiDevices)),
        reason: 'exigir faria quem recusasse perder a malha inteira por '
            'causa do acelerador',
      );
    });

    test('e continua exigindo localização e o trio', () {
      final q = MalhaService.permissoesPara(33);
      expect(q.obrigatorias, containsAll([Permission.location, ...trio]));
    });
  });

  test('localização é obrigatória em TODA versão', () {
    for (final sdk in [24, 30, 31, 33, 35, 36]) {
      expect(
        MalhaService.permissoesPara(sdk).obrigatorias,
        contains(Permission.location),
        reason: 'SDK $sdk',
      );
    }
  });

  test('nada é exigido duas vezes', () {
    for (final sdk in [24, 30, 31, 33, 36]) {
      final q = MalhaService.permissoesPara(sdk);
      final todas = [...q.obrigatorias, ...q.opcionais];
      expect(todas.toSet().length, todas.length, reason: 'SDK $sdk');
      // Obrigatória e opcional ao mesmo tempo seria contradição: o
      // `_pedirPermissoes` exigiria o que ele mesmo marcou de dispensável.
      expect(
        q.obrigatorias.toSet().intersection(q.opcionais.toSet()),
        isEmpty,
        reason: 'SDK $sdk',
      );
    }
  });
}
