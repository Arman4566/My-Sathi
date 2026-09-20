import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Copies photos and generated PDFs into the app's persistent documents
/// directory (NOT the temp/cache directory) so they're still there after
/// the app restarts or the user logs out and back in on the same device.
///
/// Why this matters: image_picker hands back a file living in the OS
/// temp/cache directory, and PDF bytes returned from the backend were
/// previously only ever written to getTemporaryDirectory() for a one-off
/// "open/share" action. Both of those can be cleared by the OS at any
/// time (low storage, app restart, cache-clearing) — they were never
/// meant for long-term storage. This service is the fix: every photo or
/// PDF the app wants to keep gets copied here once, and every screen
/// that displays "your saved reports" reads from here first.
class LocalFileStorageService {
  LocalFileStorageService._internal();
  static final LocalFileStorageService instance = LocalFileStorageService._internal();

  Future<Directory> _rootDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(docs.path, 'sathi_files'));
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    return root;
  }

  Future<Directory> _subDir(String subfolder) async {
    final root = await _rootDir();
    final dir = Directory(p.join(root.path, subfolder));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Copies [source] (e.g. an image_picker temp file) into persistent
  /// storage under [subfolder], named [filename] (include the
  /// extension). Returns the new, stable path — store THIS, not the
  /// original picker path.
  Future<String> savePickedFile(File source, {required String subfolder, required String filename}) async {
    final dir = await _subDir(subfolder);
    final dest = File(p.join(dir.path, filename));
    await source.copy(dest.path);
    return dest.path;
  }

  /// Writes raw bytes (e.g. a generated PDF from the backend) into
  /// persistent storage under [subfolder]. Returns the new path.
  Future<String> saveBytes(List<int> bytes, {required String subfolder, required String filename}) async {
    final dir = await _subDir(subfolder);
    final dest = File(p.join(dir.path, filename));
    await dest.writeAsBytes(bytes, flush: true);
    return dest.path;
  }

  Future<bool> exists(String? path) async {
    if (path == null || path.isEmpty) return false;
    return File(path).exists();
  }

  Future<void> delete(String? path) async {
    if (path == null || path.isEmpty) return;
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
