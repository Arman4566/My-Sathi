import 'dart:io';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:provider/provider.dart';
import '../services/settings_service.dart';
import '../services/app_text.dart';

/// Fullscreen, pinch-to-zoom viewer for a prescription/report image, with
/// a "save to gallery" action in the app bar. Push it with
/// [FullscreenImageViewer.open] rather than constructing it directly.
class FullscreenImageViewer extends StatefulWidget {
  final File imageFile;
  final String? title;

  const FullscreenImageViewer({super.key, required this.imageFile, this.title});

  static void open(BuildContext context, File imageFile, {String? title}) {
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) =>
            FullscreenImageViewer(imageFile: imageFile, title: title),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  State<FullscreenImageViewer> createState() => _FullscreenImageViewerState();
}

class _FullscreenImageViewerState extends State<FullscreenImageViewer> {
  bool _saving = false;

  Future<void> _save(String lang) async {
    setState(() => _saving = true);
    try {
      final hasAccess = await Gal.hasAccess() || await Gal.requestAccess();
      if (!hasAccess) {
        _showMessage(AppText.t('gallery_permission_denied', lang));
        return;
      }
      await Gal.putImage(widget.imageFile.path, album: 'My Sathi');
      _showMessage(AppText.t('saved_to_gallery', lang));
    } on GalException catch (e) {
      _showMessage('${AppText.t('save_failed', lang)}: ${e.type.message}');
    } catch (_) {
      _showMessage(AppText.t('save_failed', lang));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsService>().languageCode;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          widget.title ?? '',
          style: const TextStyle(color: Colors.white, fontSize: 16),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: AppText.t('save_to_gallery', lang),
            icon: _saving
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.download_outlined),
            onPressed: _saving ? null : () => _save(lang),
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: Image.file(widget.imageFile, fit: BoxFit.contain),
        ),
      ),
    );
  }
}

/// Small circular "view fullscreen" button meant to sit in the corner of
/// an image thumbnail (e.g. via a Stack + Positioned), used on the
/// prescription and report detail screens.
class ThumbnailFullscreenBadge extends StatelessWidget {
  final VoidCallback onTap;
  final String tooltip;

  const ThumbnailFullscreenBadge({super.key, required this.onTap, required this.tooltip});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withValues(alpha: 0.55),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: const Padding(
            padding: EdgeInsets.all(8),
            child: Icon(Icons.fullscreen, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }
}

/// Saves an image at [imagePath] to the phone's gallery, showing a
/// snackbar with the result. Safe to call from a plain [BuildContext]
/// (e.g. an AppBar action in a StatelessWidget) — checks `context.mounted`
/// after the async gap before touching the context again.
Future<void> saveImageToGallery(BuildContext context, String imagePath, String lang) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final hasAccess = await Gal.hasAccess() || await Gal.requestAccess();
    if (!context.mounted) return;
    if (!hasAccess) {
      messenger.showSnackBar(SnackBar(content: Text(AppText.t('gallery_permission_denied', lang))));
      return;
    }
    await Gal.putImage(imagePath, album: 'My Sathi');
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(AppText.t('saved_to_gallery', lang))));
  } on GalException catch (e) {
    if (!context.mounted) return;
    messenger.showSnackBar(
        SnackBar(content: Text('${AppText.t('save_failed', lang)}: ${e.type.message}')));
  } catch (_) {
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(AppText.t('save_failed', lang))));
  }
}
