import 'dart:async';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/io_client.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _CacheDirectories extends PathProviderPlatform {
  _CacheDirectories(this.directory);
  final String directory;
  @override
  Future<String> getTemporaryPath() async => directory;
}

void main() {
  final client = HttpClient();
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'covers survive cache recreation and a new URL fetches the new image',
    () async {
      final directory = await Directory.systemTemp.createTemp('prism-cache-');
      final paths = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _CacheDirectories(directory.path);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <String>[];
      final bytes = File('assets/icon/logo_icon.png').readAsBytesSync();
      server.listen((request) {
        requests.add(request.uri.toString());
        request.response.headers.set(
          'cache-control',
          'public, max-age=31536000, immutable',
        );
        request.response.headers.contentType = ContentType('image', 'png');
        request.response.add(bytes);
        unawaited(request.response.close());
      });
      CacheManager openCache() => CacheManager(
        Config(
          'heroes',
          repo: JsonCacheInfoRepository.withFile(
            File('${directory.path}/cache.json'),
          ),
          fileService: HttpFileService(httpClient: IOClient(client)),
        ),
      );
      var cache = openCache();
      Future<void> load(String version) async {
        final done = Completer<void>();
        final stream = CachedNetworkImageProvider(
          'http://127.0.0.1:${server.port}/hero?v=$version',
        ).resolve(ImageConfiguration.empty);
        final listener = ImageStreamListener(
          (image, _) {
            image.dispose();
            if (!done.isCompleted) done.complete();
          },
          onError: (Object error, StackTrace? stack) =>
              done.completeError(error, stack),
        );
        stream.addListener(listener);
        try {
          await done.future;
        } finally {
          stream.removeListener(listener);
        }
      }

      try {
        CachedNetworkImageProvider.defaultCacheManager = cache;
        await load('one');
        expect(requests, ['/hero?v=one']);
        await cache.dispose();
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
        cache = openCache();
        CachedNetworkImageProvider.defaultCacheManager = cache;
        await load('one');
        expect(requests, [
          '/hero?v=one',
        ], reason: 'must read the file, not download again');
        await load('two');
        expect(requests, ['/hero?v=one', '/hero?v=two']);
      } finally {
        await cache.dispose();
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
        PathProviderPlatform.instance = paths;
        await server.close(force: true);
        client.close(force: true);
        await directory.delete(recursive: true);
      }
    },
  );
}
