import 'package:flutter/material.dart';

import 'notifications.dart';
import 'store.dart';
import 'ui/home_shell.dart';
import 'ui/reader_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final notifications = NotificationService();
  await notifications.init();
  final store = await AppStore.open(notifications);

  void openBook(String bookId) {
    final book = store.bookById(bookId);
    if (book == null || book.finished) return;
    navigatorKey.currentState?.push(MaterialPageRoute<void>(
      builder: (_) => ReaderScreen(store: store, book: book),
    ));
  }

  notifications.onOpen = openBook;
  runApp(MicroReaderApp(store: store));

  final launchBook = await notifications.launchPayload();
  if (launchBook != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) => openBook(launchBook));
  }
  await notifications.requestPermissions();
  await store.replan();
}

class MicroReaderApp extends StatelessWidget {
  const MicroReaderApp({super.key, required this.store});

  final AppStore store;

  ThemeData _theme(Brightness brightness) => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C5CE7),
          brightness: brightness,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Micro Reader',
      navigatorKey: navigatorKey,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: HomeShell(store: store),
    );
  }
}
