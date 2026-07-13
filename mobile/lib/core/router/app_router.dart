import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/login_screen.dart';
import '../../features/auth/splash_screen.dart';
import '../../features/dashboard/back_office_home_screen.dart';
import '../../features/sales/outlet_home_screen.dart';
import '../auth/auth_session.dart';

class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Ref ref) {
    ref.listen(authSessionProvider, (previous, next) {
      if (previous?.status != next.status) notifyListeners();
    });
  }
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _AuthRefreshNotifier(ref);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final auth = ref.read(authSessionProvider);
      final location = state.matchedLocation;

      if (auth.status == AuthStatus.unknown) {
        return location == '/' ? null : '/';
      }

      if (auth.status == AuthStatus.unauthenticated) {
        return location == '/login' ? null : '/login';
      }

      final home = auth.user!.isAdmin ? '/back-office' : '/outlet';
      if (location == '/' || location == '/login') return home;
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/outlet',
        builder: (context, state) => const OutletHomeScreen(),
      ),
      GoRoute(
        path: '/back-office',
        builder: (context, state) => const BackOfficeHomeScreen(),
      ),
    ],
  );
});
