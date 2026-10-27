import 'dart:async';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'l10n/app_localizations.dart';
import 'src/application/locale_controller.dart';
import 'src/application/app_info.dart';
import 'src/application/app_instance_coordinator.dart';
import 'src/application/desktop_instance_platform.dart';
import 'src/presentation/components/app_button.dart';
import 'src/presentation/components/app_backdrop_surface.dart';
import 'src/presentation/components/app_text_input_scope.dart';
import 'src/application/app_config_store.dart';
import 'src/application/window_placement_controller.dart';
import 'src/application/window_placement_store.dart';
import 'src/domain/viewer_settings.dart';
import 'src/presentation/theme/app_theme.dart';
import 'src/presentation/theme_demo_page.dart';
import 'src/presentation/viewer_page.dart';

export 'src/presentation/viewer_page.dart' show ViewerPage;
export 'src/presentation/components/form_components.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  const themeDemoBuild = bool.fromEnvironment(
    'SHENVIEW_THEME_DEMO',
    defaultValue: false,
  );
  final themeDemo =
      themeDemoBuild ||
      arguments.any((argument) => argument.endsWith('--theme-demo'));
  const options = WindowOptions(
    size: Size(1280, 800),
    minimumSize: Size(
      WindowPlacement.minimumWidth,
      WindowPlacement.minimumHeight,
    ),
    center: true,
    title: AppInfo.englishName,
    titleBarStyle: TitleBarStyle.hidden,
    // Keep the native window surface aligned with the dark shell while the
    // Flutter child surface is being handed back after an external process
    // (for example Explorer) takes focus.
    backgroundColor: Color(0xFF1D201D),
  );
  final store = AppConfigStore();
  final initialSettings = await ViewerSettings.load(store: store);
  var request = AppLaunchRequest.fromArguments(arguments);
  AppInstanceCoordinator? instances;
  final nativeRequests = <List<String>>[];
  DesktopInstancePlatform.listen(nativeRequests.add);
  final initialFiles = await DesktopInstancePlatform.takeInitialFiles();
  if (initialFiles.isNotEmpty) request = AppLaunchRequest(paths: initialFiles);
  try {
    if (!themeDemo) {
      instances = await AppInstanceCoordinator.start(
        config: store,
        request: request,
        allowActivation: DesktopInstancePlatform.allowActivation,
      );
      if (instances == null) {
        exit(0);
      }
    }
  } on FileSystemException catch (error) {
    // A read-only or unavailable settings directory must not block viewing.
    // Without its coordination files this launch runs as an independent window.
    debugPrint(
      'Instance storage unavailable; opening independent window: $error',
    );
  } catch (error) {
    debugPrint('Instance startup failed: $error');
    final chinese = Platform.localeName.startsWith('zh');
    runApp(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    chinese ? '无法连接已有窗口或读取实例信息。请稍后重试，或关闭已有窗口后重新启动。' : 'Unable to contact the running viewer or read instance information. Retry shortly, or close the other viewer and launch again.',
                  ),
                  const SizedBox(height: 16),
                  AppButton(
                    label: chinese ? '关闭' : 'Close',
                    onPressed: () => exit(1),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
    });
    return;
  }
  await windowManager.waitUntilReadyToShow(options);
  final placement = themeDemo
      ? null
      : WindowPlacementController(WindowPlacementStore(store));
  try {
    await placement?.restore();
  } catch (error) {
    debugPrint('Unable to restore window placement: $error');
  }
  await windowManager.show();
  await windowManager.focus();
  await placement?.start();
  final localeController = AppLocaleController();
  localeController.setPreference(initialSettings.localeCode);
  void updateWindowTitle() {
    final language =
        localeController.locale?.languageCode ?? Platform.localeName;
    unawaited(windowManager.setTitle(AppInfo.localizedName(language)));
  }

  localeController.addListener(updateWindowTitle);
  updateWindowTitle();
  runApp(
    ShenViewApp(
      initialPath: themeDemo || request.paths.isEmpty
          ? null
          : request.paths.first,
      instanceCoordinator: instances,
      windowPlacement: placement,
      pendingNativeRequests: nativeRequests,
      additionalPaths: request.paths.skip(1).toList(),
      localeController: localeController,
      initialThemeMode: initialSettings.themeMode,
      initialSettings: initialSettings,
      configStore: store,
      themeDemo: themeDemo,
    ),
  );
}

class ShenViewApp extends StatefulWidget {
  const ShenViewApp({
    super.key,
    this.initialPath,
    this.instanceCoordinator,
    this.windowPlacement,
    this.pendingNativeRequests = const [],
    this.additionalPaths = const [],
    this.localeController,
    this.initialThemeMode = ViewerThemeMode.dark,
    this.initialSettings,
    this.configStore,
    this.themeDemo = false,
  });

  final String? initialPath;
  final AppInstanceCoordinator? instanceCoordinator;
  final WindowPlacementController? windowPlacement;
  final List<List<String>> pendingNativeRequests;
  final List<String> additionalPaths;
  final AppLocaleController? localeController;
  final ViewerThemeMode initialThemeMode;
  final ViewerSettings? initialSettings;
  final AppConfigStore? configStore;
  final bool themeDemo;

  @override
  State<ShenViewApp> createState() => _ShenViewAppState();
}

class _ShenViewAppState extends State<ShenViewApp> {
  late ViewerThemeMode _themeMode = widget.initialThemeMode;

  // Flutter's Windows accessibility bridge currently has an open AXTree
  // corruption bug when dynamic overlays (menus/tooltips) are attached and
  // removed. Keep an opt-in switch so the workaround can be removed once the
  // engine fix is available without changing the application code again.
  static const _enableWindowsSemantics = bool.fromEnvironment(
    'SHENVIEW_ENABLE_WINDOWS_SEMANTICS',
    defaultValue: false,
  );

  void _setThemeMode(ViewerThemeMode mode) {
    if (_themeMode == mode) return;
    setState(() => _themeMode = mode);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.localeController;
    if (controller == null) return _buildApp(null);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) => _buildApp(controller),
    );
  }

  Widget _buildApp(AppLocaleController? controller) {
    final app = MaterialApp(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      locale: controller?.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      // The viewer and settings page share the same tokenized light/dark
      // themes. The review page remains available with --theme-demo.
      themeMode: switch (_themeMode) {
        ViewerThemeMode.system => ThemeMode.system,
        ViewerThemeMode.light => ThemeMode.light,
        ViewerThemeMode.dark => ThemeMode.dark,
      },
      home: widget.themeDemo
          ? const ThemeDemoPage()
          : ViewerPage(
              initialSettings: widget.initialSettings,
              configStore: widget.configStore,
              initialPath: widget.initialPath,
              instanceCoordinator: widget.instanceCoordinator,
              windowPlacement: widget.windowPlacement,
              pendingNativeRequests: widget.pendingNativeRequests,
              additionalPaths: widget.additionalPaths,
              localeController: controller,
              onThemeModeChanged: _setThemeMode,
            ),
    );
    final textInputApp = AppTextInputScope(
      child: AppMaterialEffects(child: app),
    );
    if (Platform.isWindows && !_enableWindowsSemantics) {
      return ExcludeSemantics(child: textInputApp);
    }
    return textInputApp;
  }
}
