import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

void main() {
  testWidgets('PrettyQrView rend la clé publique sans erreur',
      (WidgetTester tester) async {
    const key =
        'pfa:v1:abcdefghijklmnopqrstuvwxyz0123456789ABCDEF0:abcdefghijklmnopqrstuvwxyz0123456789ABCDEF0';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 240,
              height: 240,
              child: PrettyQrView.data(
                data: key,
                errorCorrectLevel: QrErrorCorrectLevel.M,
                decoration: const PrettyQrDecoration(
                  shape: PrettyQrSmoothSymbol(color: Color(0xFF122019)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(PrettyQrView), findsOneWidget);
  });
}
