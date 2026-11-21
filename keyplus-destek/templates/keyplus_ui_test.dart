import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/desktop/pages/keyplus_access.dart';
import 'package:flutter_hbb/desktop/pages/keyplus_layout.dart';

void main() {
  test('unknown or malformed service states never become compatible', () {
    for (final state in [null, '', 'ready', 'error', 1, true]) {
      expect(keyplusKnownServiceState(state), 'unknown');
    }
    expect(keyplusKnownServiceState('mismatch'), 'mismatch');
    expect(keyplusKnownServiceState('compatible'), 'compatible');
  });
  test('empty and self ID warn without restricting custom IDs or IP formats',
      () {
    expect(keyplusIdError(' ', '268 304 385'), isNotNull);
    expect(keyplusIdError('268304385', '268 304 385'), isNotNull);
    for (final id in [
      '59035388',
      'support-client',
      '192.168.1.5',
      '[::1]:21118',
      '59035388@server?key=value'
    ]) {
      expect(keyplusIdError(id, '268304385'), isNull, reason: id);
    }
    expect(keyplusIdError('59035388', ''), isNull);
  });

  test(
      'access descriptions reflect click, password and either method separately',
      () {
    expect(keyplusApprovalText('click', 'use-permanent-password'),
        contains('Her bağlantı isteği'));
    expect(keyplusApprovalText('password', 'use-permanent-password'),
        contains('kalıcı parolanızla'));
    expect(keyplusApprovalText('password', 'use-temporary-password'),
        contains('tek kullanımlık parolayla'));
    expect(keyplusApprovalText('', 'use-both-passwords'),
        contains('veya bu bilgisayardan'));
    expect(keyplusApprovalText('password-click', 'use-both-passwords'),
        contains('veya bu bilgisayardan'));
    expect(keyplusApprovalText('unknown', ''), contains('kontrol edin'));
  });

  for (final size in [
    const Size(1200, 720),
    const Size(900, 560),
    const Size(420, 600)
  ]) {
    testWidgets('task panels remain reachable at $size and 200% text scale',
        (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var copied = false;
      await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(
                  body: KeyplusTaskLayout(
                header: const Padding(
                    padding: EdgeInsets.all(16), child: Text('Keyplus Destek')),
                receive: Column(children: [
                  const Text('Destek alın'),
                  const SelectableText('268 304 385'),
                  OutlinedButton(
                      onPressed: () => copied = true,
                      child: const Text('Kimliği kopyala'))
                ]),
                connection: const Column(children: [
                  Text('Bilgisayara bağlanın'),
                  TextField(
                      decoration: InputDecoration(
                          labelText: 'Karşı bilgisayarın kimliği')),
                  Expanded(child: Center(child: Text('Son bağlantılar')))
                ]),
              )))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Kimliği kopyala'));
      expect(copied, isTrue);
      await tester.ensureVisible(find.text('Son bağlantılar'));
      expect(tester.takeException(), isNull);
    });
  }
}
