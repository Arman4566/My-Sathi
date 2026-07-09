import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../services/auth_service.dart';
import '../services/cloud_sync_service.dart';
import 'home_screen.dart';
import 'login_screen.dart';

/// Shown immediately on launch while we check whether a login session
/// already exists. Guarantees a minimum display time so it doesn't just
/// flash for a frame on fast devices — a bare "flash" reads as a glitch,
/// a deliberate short pause reads as a loading screen.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final stopwatch = Stopwatch()..start();
    final profile = await AuthService.instance.getCurrentProfile();
    if (profile != null) {
      // Non-blocking: keeps app launch fast; the home screen's own
      // pull-to-refresh (and RefreshIndicator) will pick up anything
      // this brings down from another device.
      unawaited(CloudSyncService.instance.pullAllAndMerge());
    }

    const minSplashTime = Duration(milliseconds: 1400);
    final elapsed = stopwatch.elapsed;
    if (elapsed < minSplashTime) {
      await Future.delayed(minSplashTime - elapsed);
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => profile != null ? const HomeScreen() : const LoginScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF5B7CFA), Color(0xFF7B61FF)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 3),
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(32),
                ),
                child: const Icon(Icons.monitor_heart_outlined,
                    size: 64, color: Colors.white),
              ),
              const SizedBox(height: 20),
              const Text('Sathi',
                  style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              const SizedBox(height: 6),
              Text('Your health companion',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.85))),
              const Spacer(flex: 3),
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
