import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/adapters.dart';
import 'package:integration_test/integration_test.dart';
import 'package:subtitle_downloader/features/main/app_navigation.dart';
import 'package:subtitle_downloader/features/firestore/repos/firestore_service.dart';
import 'package:subtitle_downloader/firebase_options.dart';
import 'package:subtitle_downloader/hive/settings_box.dart';
import 'package:subtitle_downloader/main.dart';

/// Environment variables for login credentials.
/// Pass via: --dart-define=TEST_EMAIL=... --dart-define=TEST_PASSWORD=...
const _testEmail = String.fromEnvironment('TEST_EMAIL');
const _testPassword = String.fromEnvironment('TEST_PASSWORD');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('App Screenshots', () {
    setUpAll(() async {
      await dotenv.load(fileName: '.env');
      await Hive.initFlutter();
      await Hive.openBox('settingsBox');
      await Hive.openBox('recentSearchesBox');
      await Hive.openBox('downloadedSubtitlesBox');
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      FirestoreService().startListener();
    });

    testWidgets('take screenshots of all main screens', (tester) async {
      // Ensure we start in light mode
      if (SettingsBox.getThemeMode() == 'dark') {
        SettingsBox.toggleThemeMode();
      }

      await tester.pumpWidget(const MyApp());
      await _pumpFrames(tester);
      await binding.convertFlutterSurfaceToImage();

      // ── Light mode screenshots ──────────────────────────────────────
      await _takeAllScreenshots(tester, binding, prefix: 'light');

      // ── Switch to dark mode ─────────────────────────────────────────
      SettingsBox.toggleThemeMode();
      await _pumpFrames(tester);

      // ── Dark mode screenshots ───────────────────────────────────────
      await _takeAllScreenshots(tester, binding, prefix: 'dark');

      // Restore light mode
      if (SettingsBox.getThemeMode() == 'dark') {
        SettingsBox.toggleThemeMode();
      }
    });
  });
}

/// Takes all app screenshots with the given filename [prefix].
Future<void> _takeAllScreenshots(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding, {
  required String prefix,
}) async {
  // ── 1. Home Movies ────────────────────────────────────────────────
  await _tapBottomNavItem(tester, 'Movies');
  await _waitForContent(tester);
  await binding.takeScreenshot('${prefix}_01_home_movies');

  // ── 2. Home TV ────────────────────────────────────────────────────
  await _tapBottomNavItem(tester, 'TV');
  await _waitForContent(tester);
  await binding.takeScreenshot('${prefix}_02_home_tv');

  // ── 3. Login (navigate via Profile tab) ───────────────────────────
  await _tapBottomNavItem(tester, 'Profile');
  await _pumpFrames(tester);

  final loginTile = find.text('Login or Sign Up');
  if (loginTile.evaluate().isNotEmpty) {
    await tester.tap(loginTile);
    await _pumpFrames(tester);

    if (_testEmail.isNotEmpty && _testPassword.isNotEmpty) {
      await tester.enterText(
        find.byType(TextFormField).first,
        _testEmail,
      );
      await tester.enterText(
        find.byType(TextFormField).last,
        _testPassword,
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
      await _pumpFrames(tester, seconds: 5);
    } else {
      await binding.takeScreenshot('${prefix}_03_login_page');
      AppNavigation.router.pop();
      await _pumpFrames(tester);
    }
  }

  // ── 4. Profile page (logged-in or not) ────────────────────────────
  await binding.takeScreenshot('${prefix}_04_profile');

  // ── 5. Settings ───────────────────────────────────────────────────
  final settingsIcon = find.byIcon(Icons.settings_rounded);
  if (settingsIcon.evaluate().isNotEmpty) {
    await tester.tap(settingsIcon);
    await _pumpFrames(tester);
    await binding.takeScreenshot('${prefix}_05_settings');
    AppNavigation.router.pop();
    await _pumpFrames(tester);
  }

  // ── 6. Movie detail page ──────────────────────────────────────────
  AppNavigation.router.pushNamed('View Movie', pathParameters: {
    'movieId': '550',
    'movieName': 'Fight Club',
  });
  await _pumpFrames(tester, seconds: 3);
  await _waitForContent(tester);
  await binding.takeScreenshot('${prefix}_06_movie_detail');

  AppNavigation.router.pop();
  await _pumpFrames(tester);

  // File Manager tab is skipped — it triggers a system permission
  // dialog (All Files Access) that can't be handled in integration tests.
}

/// Tap a bottom navigation item by its label.
Future<void> _tapBottomNavItem(WidgetTester tester, String label) async {
  final item = find.descendant(
    of: find.byType(BottomNavigationBar),
    matching: find.text(label),
  );
  expect(item, findsOneWidget);
  await tester.tap(item);
  await _pumpFrames(tester);
}

/// Pump frames for [seconds] without waiting for animations to fully settle.
Future<void> _pumpFrames(WidgetTester tester, {int seconds = 2}) async {
  for (int i = 0; i < seconds * 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Pump frames until loading indicators disappear or timeout.
Future<void> _waitForContent(WidgetTester tester) async {
  for (int i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 500));
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
  }
  await _pumpFrames(tester);
}
