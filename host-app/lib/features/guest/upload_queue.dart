import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import '../../utils/guest_prefs.dart';

/// Кадр, ожидающий отправки на сервер. Хранится на диске: переживает закрытие экрана
/// камеры и перезапуск приложения, поэтому снятое фото не пропадает при плохой сети.
class UploadJob {
  final String id;
  final String eventId;
  final String filePath;
  final int width;
  final int height;
  final String capturedAt;
  String? frameId;
  String? uploadUrl;
  int urlAtMs;
  int attempts;
  int nextAtMs;
  final int createdAtMs;

  UploadJob({
    required this.id,
    required this.eventId,
    required this.filePath,
    required this.width,
    required this.height,
    required this.capturedAt,
    this.frameId,
    this.uploadUrl,
    this.urlAtMs = 0,
    this.attempts = 0,
    this.nextAtMs = 0,
    int? createdAtMs,
  }) : createdAtMs = createdAtMs ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, Object?> toJson() => {
        'id': id,
        'eventId': eventId,
        'filePath': filePath,
        'width': width,
        'height': height,
        'capturedAt': capturedAt,
        'frameId': frameId,
        'uploadUrl': uploadUrl,
        'urlAtMs': urlAtMs,
        'attempts': attempts,
        'nextAtMs': nextAtMs,
        'createdAtMs': createdAtMs,
      };

  static UploadJob fromJson(Map<String, dynamic> m) => UploadJob(
        id: m['id'] as String,
        eventId: m['eventId'] as String,
        filePath: m['filePath'] as String,
        width: m['width'] as int,
        height: m['height'] as int,
        capturedAt: m['capturedAt'] as String,
        frameId: m['frameId'] as String?,
        uploadUrl: m['uploadUrl'] as String?,
        urlAtMs: (m['urlAtMs'] as num?)?.toInt() ?? 0,
        attempts: (m['attempts'] as num?)?.toInt() ?? 0,
        nextAtMs: (m['nextAtMs'] as num?)?.toInt() ?? 0,
        createdAtMs: (m['createdAtMs'] as num?)?.toInt(),
      );
}

/// Очередь загрузки кадров: до [_maxParallel] кадров одновременно, повтор с нарастающей
/// паузой при обрыве сети и 5xx, продолжение после перезапуска. Один и тот же кадр
/// на повторе берёт новый URL у сервера (`resume_frame_id`) и не занимает второе
/// место в квоте.
class UploadQueue extends ChangeNotifier with WidgetsBindingObserver {
  UploadQueue._();
  static final UploadQueue instance = UploadQueue._();

  static const _maxParallel = 2;
  static const _urlTtlMs = 50 * 60 * 1000;
  static const _maxAgeMs = 3 * 24 * 3600 * 1000;

  final List<UploadJob> _jobs = [];
  final Set<String> _running = {};
  final Map<String, Completer<String>> _waiters = {};
  final Map<String, CancelToken?> _tokens = {};
  Dio? _dio;
  Dio? _s3;
  bool _loaded = false;
  Timer? _timer;
  Directory? _dir;

  int pendingFor(String eventId) => _jobs.where((j) => j.eventId == eventId).length;
  int get pendingTotal => _jobs.length;

  /// Вызывается при старте приложения: поднимает сохранённые кадры и продолжает отправку.
  Future<void> attach(Dio dio) async {
    _dio = dio;
    _s3 ??= Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(minutes: 3),
      receiveTimeout: const Duration(seconds: 60),
    ));
    if (!_loaded) {
      _loaded = true;
      WidgetsBinding.instance.addObserver(this);
      await _loadFromDisk();
    }
    _pump();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      for (final j in _jobs) {
        j.nextAtMs = 0;
      }
      _pump();
    }
  }

  Future<Directory> _queueDir() async {
    final d = _dir;
    if (d != null) return d;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/upload_queue');
    if (!await dir.exists()) await dir.create(recursive: true);
    return _dir = dir;
  }

  Future<void> _loadFromDisk() async {
    try {
      final dir = await _queueDir();
      for (final f in dir.listSync()) {
        if (f is! File || !f.path.endsWith('.json')) continue;
        try {
          final job = UploadJob.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
          if (!await File(job.filePath).exists()) {
            await f.delete();
            continue;
          }
          if (!_jobs.any((j) => j.id == job.id)) _jobs.add(job);
        } catch (_) {
          // Битую запись пропускаем.
        }
      }
      _jobs.sort((a, b) => a.createdAtMs.compareTo(b.createdAtMs));
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _persist(UploadJob job) async {
    try {
      final dir = await _queueDir();
      await File('${dir.path}/${job.id}.json').writeAsString(jsonEncode(job.toJson()));
    } catch (_) {}
  }

  Future<void> _forget(UploadJob job) async {
    _jobs.removeWhere((j) => j.id == job.id);
    _tokens.remove(job.id);
    try {
      final dir = await _queueDir();
      final meta = File('${dir.path}/${job.id}.json');
      if (await meta.exists()) await meta.delete();
      final img = File(job.filePath);
      if (await img.exists()) await img.delete();
    } catch (_) {}
    notifyListeners();
  }

  /// Ставит кадр в очередь. Возвращает Future с frame_id: завершается успехом, когда кадр
  /// зарегистрирован на сервере, и ошибкой только при отмене или окончательном отказе.
  /// Временные сбои сети не приводят к ошибке — отправка повторяется.
  Future<String> enqueue({
    required Dio dio,
    required String eventId,
    required Uint8List bytes,
    required int width,
    required int height,
    String? capturedAt,
    CancelToken? cancelToken,
  }) async {
    _dio = dio;
    _s3 ??= Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(minutes: 3),
      receiveTimeout: const Duration(seconds: 60),
    ));
    if (!_loaded) {
      _loaded = true;
      WidgetsBinding.instance.addObserver(this);
      await _loadFromDisk();
    }
    final dir = await _queueDir();
    final id = '${DateTime.now().microsecondsSinceEpoch}_${math.Random().nextInt(1 << 30)}';
    final path = '${dir.path}/$id.jpg';
    await File(path).writeAsBytes(bytes, flush: true);
    final job = UploadJob(
      id: id,
      eventId: eventId,
      filePath: path,
      width: width,
      height: height,
      capturedAt: capturedAt ?? DateTime.now().toUtc().toIso8601String(),
    );
    await _persist(job);
    final completer = Completer<String>();
    _waiters[id] = completer;
    _tokens[id] = cancelToken;
    _jobs.add(job);
    notifyListeners();
    _pump();
    return completer.future;
  }

  void _pump() {
    final dio = _dio;
    if (dio == null) return;
    _timer?.cancel();
    final now = DateTime.now().millisecondsSinceEpoch;
    int? soonest;
    for (final job in List<UploadJob>.from(_jobs)) {
      if (_running.contains(job.id)) continue;
      if (job.nextAtMs > now) {
        soonest = soonest == null ? job.nextAtMs : math.min(soonest, job.nextAtMs);
        continue;
      }
      if (_running.length >= _maxParallel) break;
      _running.add(job.id);
      unawaited(_run(job, dio));
    }
    if (soonest != null) {
      _timer = Timer(Duration(milliseconds: math.max(500, soonest - now)), _pump);
    }
  }

  bool _isCancelled(UploadJob job) => _tokens[job.id]?.isCancelled ?? false;

  Future<void> _run(UploadJob job, Dio dio) async {
    try {
      if (_isCancelled(job)) throw DioException.requestCancelled(requestOptions: RequestOptions(), reason: 'user-discarded');
      final guestToken = await GuestPrefs.tokenFor(job.eventId);
      if (guestToken.isEmpty) {
        throw DioException(
          requestOptions: RequestOptions(),
          type: DioExceptionType.badResponse,
          response: Response(requestOptions: RequestOptions(), statusCode: 401),
        );
      }
      final opts = Options(headers: {'X-Guest-Token': guestToken});
      final token = _tokens[job.id];

      final now = DateTime.now().millisecondsSinceEpoch;
      if (job.frameId == null || job.uploadUrl == null || now - job.urlAtMs > _urlTtlMs) {
        final bytesLen = await File(job.filePath).length();
        final presign = await dio.post(
          'guest/frames/presign',
          data: {
            'content_type': 'image/jpeg',
            'size_bytes': bytesLen,
            if (job.frameId != null) 'resume_frame_id': job.frameId,
          },
          options: opts,
          cancelToken: token,
        );
        final data = presign.data;
        final frameId = (data is Map ? data['frame_id'] : null) as String?;
        final url = (data is Map ? data['upload_url'] : null) as String?;
        if (frameId == null || url == null) throw StateError('presign');
        job.frameId = frameId;
        job.uploadUrl = url;
        job.urlAtMs = now;
        await _persist(job);
      }

      final bytes = await File(job.filePath).readAsBytes();
      try {
        await _s3!.put(
          job.uploadUrl!,
          data: Stream.fromIterable([bytes]),
          options: Options(
            headers: {'Content-Type': 'image/jpeg', 'Content-Length': bytes.length.toString()},
            validateStatus: (s) => s != null && s < 300,
          ),
          cancelToken: token,
        );
      } on DioException catch (e) {
        // Просроченная подпись: на следующей попытке запросим новый URL для того же кадра.
        if (e.response?.statusCode == 403) {
          job.uploadUrl = null;
          await _persist(job);
        }
        rethrow;
      }

      await dio.post(
        'guest/frames/',
        data: {
          'frame_id': job.frameId,
          'captured_at': job.capturedAt,
          'width': job.width,
          'height': job.height,
        },
        options: opts,
        cancelToken: token,
      );

      final frameId = job.frameId!;
      final cancelledMeanwhile = _isCancelled(job);
      await _forget(job);
      final w = _waiters.remove(job.id);
      if (cancelledMeanwhile) {
        await _deleteOnServer(dio, job, frameId);
        if (w != null && !w.isCompleted) w.completeError('user-discarded');
      } else if (w != null && !w.isCompleted) {
        w.complete(frameId);
      }
    } catch (e) {
      await _handleFailure(job, dio, e);
    } finally {
      _running.remove(job.id);
      _pump();
    }
  }

  Future<void> _deleteOnServer(Dio dio, UploadJob job, String frameId) async {
    try {
      final guestToken = await GuestPrefs.tokenFor(job.eventId);
      await dio.delete(
        'events/${job.eventId}/frames/$frameId',
        options: Options(headers: {'X-Guest-Token': guestToken}),
      );
    } catch (_) {}
  }

  Future<void> _handleFailure(UploadJob job, Dio dio, Object e) async {
    final cancelled = _isCancelled(job) || (e is DioException && CancelToken.isCancel(e));
    if (cancelled) {
      final frameId = job.frameId;
      await _forget(job);
      if (frameId != null) await _deleteOnServer(dio, job, frameId);
      final w = _waiters.remove(job.id);
      if (w != null && !w.isCompleted) w.completeError(e);
      return;
    }

    final status = e is DioException ? e.response?.statusCode : null;
    final tooOld = DateTime.now().millisecondsSinceEpoch - job.createdAtMs > _maxAgeMs;
    // 4xx — окончательный отказ (событие закрыто, нет прав, плохой запрос), кроме 408/429
    // и 403: 403 от хранилища означает просроченную подпись, повторим с новым URL.
    final permanent = tooOld ||
        (status != null && status >= 400 && status < 500 && status != 408 && status != 429 && status != 403);
    if (permanent) {
      final frameId = job.frameId;
      await _forget(job);
      if (frameId != null) await _deleteOnServer(dio, job, frameId);
      final w = _waiters.remove(job.id);
      if (w != null && !w.isCompleted) w.completeError(e);
      return;
    }

    job.attempts += 1;
    final delaySec = math.min(60, 2 << math.min(job.attempts, 5));
    job.nextAtMs = DateTime.now().millisecondsSinceEpoch + delaySec * 1000;
    await _persist(job);
    notifyListeners();
  }
}
