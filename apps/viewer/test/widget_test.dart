import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/main.dart';
import 'package:shen_view/src/application/locale_controller.dart';

void main() {
  testWidgets('switches between English and Chinese', (tester) async {
    final locales = AppLocaleController()..setPreference('en');
    await tester.pumpWidget(ShenViewApp(localeController: locales));
    await tester.pump();
    expect(find.byIcon(FluentIcons.image_24_regular), findsOneWidget);
    expect(find.byTooltip('Settings'), findsNothing);
    expect(find.text('ShenView'), findsOneWidget);

    locales.setPreference('zh');
    await tester.pump();
    expect(find.byTooltip('设置'), findsNothing);
    expect(find.text('神羊看图'), findsOneWidget);
  });
}
