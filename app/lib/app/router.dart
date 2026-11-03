import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:my_fitness/app/app_shell.dart';
import 'package:my_fitness/core/supabase/supabase_providers.dart';
import 'package:my_fitness/features/auth/login_page.dart';
import 'package:my_fitness/features/auth/register_page.dart';
import 'package:my_fitness/features/calendar/calendar_page.dart';
import 'package:my_fitness/features/exercises/exercise_detail_page.dart';
import 'package:my_fitness/features/exercises/exercises_page.dart';
import 'package:my_fitness/features/library/library_page.dart';
import 'package:my_fitness/features/library/program_detail_page.dart';
import 'package:my_fitness/features/library/session_detail_page.dart';
import 'package:my_fitness/features/plan/plan_edit_page.dart';
import 'package:my_fitness/features/plan/plan_page.dart';
import 'package:my_fitness/features/plan/template_edit_page.dart';
import 'package:my_fitness/features/profile/profile_page.dart';
import 'package:my_fitness/features/stats/stats_page.dart';
import 'package:my_fitness/features/today/today_page.dart';
import 'package:my_fitness/features/workout/workout_page.dart';
import 'package:my_fitness/features/workout/workout_pick_page.dart';
import 'package:my_fitness/features/workout/workout_repository.dart';
import 'package:my_fitness/features/workout/workout_summary_page.dart';

/// 登录状态变化时通知路由重新判断跳转。
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Stream<AuthState> stream) {
    _sub = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<AuthState> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

const _authPaths = {'/login', '/register'};

String? authRedirect({required bool loggedIn, required String location}) {
  final onAuthPage = _authPaths.contains(location);
  if (!loggedIn && !onAuthPage) return '/login';
  if (loggedIn && onAuthPage) return '/today';
  return null;
}

/// 模板编辑、给模板选动作、选动作时看到的动作详情（带「添加动作」）。
final List<RouteBase> templateRoutes = [
  GoRoute(
    path: '/template/:id',
    builder: (_, state) => TemplateEditPage(templateId: state.pathParameters['id']!),
    routes: [
      GoRoute(
        path: 'pick',
        builder: (_, state) => TemplatePickPage(templateId: state.pathParameters['id']!),
        routes: [
          GoRoute(
            path: ':slug',
            builder: (_, state) => TemplatePickDetailPage(
              templateId: state.pathParameters['id']!,
              slug: state.pathParameters['slug']!,
            ),
          ),
        ],
      ),
    ],
  ),
];

final routerProvider = Provider<GoRouter>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final refresh = _AuthRefresh(client.auth.onAuthStateChange);
  ref.onDispose(refresh.dispose);

  final router = GoRouter(
    initialLocation: '/today',
    refreshListenable: refresh,
    redirect: (context, state) => authRedirect(
      loggedIn: client.auth.currentSession != null,
      location: state.matchedLocation,
    ),
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterPage()),
      GoRoute(path: '/me', builder: (_, _) => const ProfilePage()),
      GoRoute(
        path: '/exercise/:slug',
        builder: (_, state) => ExerciseDetailPage(slug: state.pathParameters['slug']!),
      ),
      ...templateRoutes,
      GoRoute(path: '/library', builder: (_, _) => const LibraryPage()),
      GoRoute(
        path: '/library/:slug',
        builder: (_, state) => ProgramDetailPage(slug: state.pathParameters['slug']!),
        routes: [
          GoRoute(
            path: ':key',
            builder: (_, state) => SessionDetailPage(
              slug: state.pathParameters['slug']!,
              sessionKey: state.pathParameters['key']!,
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/plan/:id',
        builder: (_, state) => PlanEditPage(planId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/workout', builder: (_, _) => const WorkoutPage()),
      GoRoute(path: '/workout/pick', builder: (_, _) => const WorkoutPickPage()),
      GoRoute(
        path: '/workout/summary',
        redirect: (_, state) => state.extra is WorkoutSummary ? null : '/today',
        builder: (_, state) => WorkoutSummaryPage(summary: state.extra! as WorkoutSummary),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/today', builder: (_, _) => const TodayPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/plan', builder: (_, _) => const PlanPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/calendar', builder: (_, _) => const CalendarPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/exercises', builder: (_, _) => const ExercisesPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/stats', builder: (_, _) => const StatsPage()),
          ]),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
