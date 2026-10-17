import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

/// Скачивает файл во временную папку под уникальным именем и проверяет целостность:
/// длина совпадает с Content-Length, у JPEG есть начало (FFD8) и конец (FFD9).
/// Общий постоянный путь недопустим: два скачивания подряд писали в один файл
/// и давали «битую» картинку с цветными полосами.
Future<File> downloadVerified(String url, {String ext = 'jpg', int attempts = 3}) async {
  final dir = await getTemporaryDirectory();
  Object? lastError;
  for (var i = 0; i < attempts; i++) {
    final path = '${dir.path}/im_${DateTime.now().microsecondsSinceEpoch}_$i.$ext';
    try {
      final resp = await Dio().download(
        url,
        path,
        deleteOnError: true,
        options: Options(receiveTimeout: const Duration(minutes: 3), headers: {'Accept-Encoding': 'identity'}),
      );
      final file = File(path);
      final length = await file.length();
      final expected = int.tryParse(resp.headers.value(Headers.contentLengthHeader) ?? '');
      if (expected != null && expected != length) {
        throw FileSystemException('Файл скачан не полностью: $length из $expected', path);
      }
      if (ext == 'jpg' || ext == 'jpeg') {
        final raf = await file.open();
        try {
          final head = await raf.read(2);
          await raf.setPosition(length - 2);
          final tail = await raf.read(2);
          if (head.length < 2 || head[0] != 0xFF || head[1] != 0xD8 || tail.length < 2 || tail[0] != 0xFF || tail[1] != 0xD9) {
            throw FileSystemException('Файл повреждён при скачивании', path);
          }
        } finally {
          await raf.close();
        }
      }
      return file;
    } catch (e) {
      lastError = e;
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
      await Future<void>.delayed(Duration(milliseconds: 400 * (i + 1)));
    }
  }
  throw lastError ?? StateError('Не удалось скачать файл');
}
