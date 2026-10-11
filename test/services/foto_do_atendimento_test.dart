import 'package:flutter_test/flutter_test.dart';
import 'package:legendario_connect/offline/outbox.dart';
import 'package:legendario_connect/services/atendimento_service.dart';

/// O bug: **da segunda foto em diante, a linha era descartada.**
///
/// Todas as fotos de um atendimento iam para o servidor com
/// `'client_id': <client_id do ATENDIMENTO>`, o mesmo valor para todas, e
/// `atendimento_fotos.client_id` tem índice único. O envio usa
/// `ignoreDuplicates: true`, então: o arquivo subia para o Storage, a
/// linha batia no índice e era **ignorada em silêncio**. Resultado — foto
/// clínica órfã, bytes no servidor que nenhuma consulta alcança.
///
/// O segundo bug, no nome do arquivo: era `'<atendimento>-${n+1}'`, com n
/// = quantidade de fotos na tela. Tirar duas fotos, apagar a primeira e
/// tirar outra gerava `-2` de novo, e o `File.copy` **sobrescrevia** a
/// foto que já estava lá.
void main() {
  group('clientIdDaFoto', () {
    test('desfaz o nome que guardarFoto monta', () {
      // `guardarFoto` grava em `<pasta>/<clientId><extensao>`. Esta função
      // é o inverso, e é ela que leva o id até o payload.
      const id = '3f2504e0-4f89-41d3-9a0c-0305e82c3301';
      expect(
        AtendimentoService.clientIdDaFoto('/data/fotos/$id.jpg'),
        id,
      );
    });

    test('funciona com separador do Windows', () {
      const id = '3f2504e0-4f89-41d3-9a0c-0305e82c3301';
      expect(
        AtendimentoService.clientIdDaFoto('C:\\app\\fotos\\$id.png'),
        id,
      );
    });

    test('ida e volta: o que sai de novoClientId volta inteiro', () {
      // `atendimento_fotos.client_id` é `uuid` no Postgres. Se o nome do
      // arquivo deixar de ser um uuid, o envio é recusado com erro de
      // tipo — classificado como PERMANENTE e mandado para quarentena.
      for (var i = 0; i < 50; i++) {
        final id = Outbox.novoClientId();
        expect(AtendimentoService.clientIdDaFoto('/x/$id.jpg'), id);
        expect(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-'
            r'[0-9a-f]{12}$',
          ).hasMatch(id),
          isTrue,
          reason: 'tem de ser uuid v4 valido: $id',
        );
      }
    });

    test('ids de fotos diferentes nunca colidem', () {
      // O contador antigo colidia depois de remover uma foto. Um uuid por
      // foto não tem como.
      final ids = {for (var i = 0; i < 500; i++) Outbox.novoClientId()};
      expect(ids.length, 500);
    });
  });
}
