import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class MyCacheManager extends CacheManager with ImageCacheManager {
  static const key = 'libCachedImageData';

  static final MyCacheManager _instance = MyCacheManager._();

  factory MyCacheManager() {
    return _instance;
  }

  MyCacheManager._()
      : super(
          Config(
            key,
            stalePeriod: const Duration(
              days: 1,
            ),
          ),
        );
}
