import 'dart:io';
import 'package:cached_video_player_plus/cached_video_player_plus.dart';
//import 'package:flutter/foundation.dart';
//import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class VideoUtils {
  VideoUtils._();

  // Cache manager to handle caching of video files.
  //final _cacheManager = DefaultCacheManager();

  // Singleton instance of VideoUtils.
  static final VideoUtils instance = VideoUtils._();

  // Method to create a VideoPlayerController from a URL.
  // If cacheFile is true, it attempts to cache the video file.
  Future<CachedVideoPlayerPlusController> videoControllerFromUrl({
    required String url,
    //bool? cacheFile = false,
    VideoPlayerOptions? videoPlayerOptions,
  }) async {
    /*try {
      File? cachedVideo;
      // If caching is enabled, try to get the cached file.
      if (cacheFile ?? false) {
        cachedVideo = await _cacheManager.getSingleFile(url);
      }
      // If a cached video file is found, create a VideoPlayerController from it.
      if (cachedVideo != null) {
        return CachedVideoPlayerPlusController.file(
          cachedVideo,
          videoPlayerOptions: videoPlayerOptions,
        );
      }
    } catch (e) {
      debugPrint(e.toString());
    }*/
    // If no cached file is found, create a VideoPlayerController from the network URL.
    return CachedVideoPlayerPlusController.networkUrl(
      Uri.parse(url),
      videoPlayerOptions: videoPlayerOptions,
      isStoryMode: true,
    );
  }

  // Method to create a VideoPlayerController from a local file.
  CachedVideoPlayerPlusController videoControllerFromFile({
    required File file,
    VideoPlayerOptions? videoPlayerOptions,
  }) {
    return CachedVideoPlayerPlusController.file(
      file,
      videoPlayerOptions: videoPlayerOptions,
      isStoryMode: true,
    );
  }

  // Method to create a VideoPlayerController from an asset file.
  CachedVideoPlayerPlusController videoControllerFromAsset({
    required String assetPath,
    VideoPlayerOptions? videoPlayerOptions,
  }) {
    return CachedVideoPlayerPlusController.asset(
      assetPath,
      videoPlayerOptions: videoPlayerOptions,
      isStoryMode: true,
    );
  }
}
