import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pfa_mobile/shared/widgets/message_bubble.dart';

void main() {
  testWidgets('MessageBubble affiche le texte et s\'aligne selon l\'auteur',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              MessageBubble(text: 'Bonjour', isMine: true),
              MessageBubble(text: 'Salut', isMine: false),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Bonjour'), findsOneWidget);
    expect(find.text('Salut'), findsOneWidget);

    final mine = tester.widget<Align>(
      find.ancestor(of: find.text('Bonjour'), matching: find.byType(Align)),
    );
    expect(mine.alignment, Alignment.centerRight);

    final theirs = tester.widget<Align>(
      find.ancestor(of: find.text('Salut'), matching: find.byType(Align)),
    );
    expect(theirs.alignment, Alignment.centerLeft);
  });
}
