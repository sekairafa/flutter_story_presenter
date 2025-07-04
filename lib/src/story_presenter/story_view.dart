import 'dart:async';
import 'dart:developer';

import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_story_presenter/src/story_presenter/story_custom_view_wrapper.dart';
import 'package:just_audio/just_audio.dart';
import '../story_presenter/story_view_indicator.dart';
import '../models/story_item.dart';
import '../models/story_view_indicator_config.dart';
import '../controller/flutter_story_controller.dart';
import '../story_presenter/image_story_view.dart';
import '../story_presenter/video_story_view.dart';
import '../story_presenter/web_story_view.dart';
import '../story_presenter/text_story_view.dart';
import '../utils/smooth_video_progress.dart';
import '../utils/story_utils.dart';

typedef OnStoryChanged = void Function(int);
typedef OnCompleted = Future<void> Function();
typedef OnLeftTap = void Function();
typedef OnRightTap = void Function();
typedef OnDrag = void Function();
typedef OnItemBuild = Widget? Function(int, Widget);
typedef OnVideoLoad = void Function(CachedVideoPlayerPlusController?);
typedef OnAudioLoaded = void Function(AudioPlayer);
typedef CustomViewBuilder = Widget Function(AudioPlayer);
typedef OnSlideDown = void Function(DragUpdateDetails);
typedef OnSlideStart = void Function(DragStartDetails);

class FlutterStoryPresenter extends StatefulWidget {
  const FlutterStoryPresenter({
    this.flutterStoryController,
    this.items = const [],
    this.onStoryChanged,
    this.onLeftTap,
    this.onRightTap,
    this.onCompleted,
    this.onPreviousCompleted,
    this.initialIndex = 0,
    this.storyViewIndicatorConfig,
    this.restartOnCompleted = true,
    this.autoPlay = true,
    this.canResume = true,
    this.canGoBack = false,
    this.onItemLoaded,
    this.onVideoLoad,
    this.headerWidget,
    this.footerWidget,
    this.onSlideDown,
    this.onSlideStart,
    super.key,
  }) : assert(initialIndex < items.length);

  final bool autoPlay;
  final bool canResume;
  final bool canGoBack;
  final void Function(int index)? onItemLoaded;

  /// List of StoryItem objects to display in the story view.
  final List<StoryItem> items;

  /// Controller for managing the current playing media.
  final FlutterStoryController? flutterStoryController;

  /// Callback function triggered whenever the story changes or the user navigates to the previous/next story.
  final OnStoryChanged? onStoryChanged;

  /// Callback function triggered when all items in the list have been played.
  final OnCompleted? onCompleted;

  /// Callback function triggered when all items in the list have been played.
  final OnCompleted? onPreviousCompleted;

  /// Callback function triggered when the user taps on the left half of the screen.
  final OnLeftTap? onLeftTap;

  /// Callback function triggered when the user taps on the right half of the screen.
  final OnRightTap? onRightTap;

  /// Callback function triggered when user drag downs the storyview.
  final OnSlideDown? onSlideDown;

  /// Callback function triggered when user starts drag downs the storyview.
  final OnSlideStart? onSlideStart;

  /// Indicates whether the story view should restart from the beginning after all items have been played.
  final bool restartOnCompleted;

  /// Index to start playing the story from initially.
  final int initialIndex;

  /// Configuration and styling options for the story view indicator.
  final StoryViewIndicatorConfig? storyViewIndicatorConfig;

  /// Callback function to retrieve the VideoPlayerController when it is initialized and ready to play.
  final OnVideoLoad? onVideoLoad;

  /// Widget to display user profile or other details at the top of the screen.
  final Widget? headerWidget;

  /// Widget to display text field or other content at the bottom of the screen.
  final Widget? footerWidget;

  @override
  State<FlutterStoryPresenter> createState() => _FlutterStoryPresenterState();
}

class _FlutterStoryPresenterState extends State<FlutterStoryPresenter>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  AnimationController? _animationController;
  Animation? _currentProgressAnimation;
  int _currentIndex = 0;
  bool _autoPlay = true;
  bool _wasDisposed = false;
  double _currentItemProgress = 0;
  CachedVideoPlayerPlusController? _currentVideoPlayer;
  AudioPlayer? _audioPlayer;
  Duration? _totalAudioDuration;
  StreamSubscription? _audioDurationSubscriptionStream;
  StreamSubscription? _audioPlayerStateStream;

  @override
  void initState() {
    _autoPlay = widget.autoPlay;
    if (_animationController != null) {
      _animationController?.reset();
      _animationController?.dispose();
      _animationController = null;
    }
    _animationController = AnimationController(
      vsync: this,
    );
    _currentIndex = widget.initialIndex;
    widget.flutterStoryController?.addListener(_storyControllerListener);
    _startStoryView();

    WidgetsBinding.instance.addObserver(this);

    super.initState();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    log("STATE ==> $state");
    switch (state) {
      case AppLifecycleState.resumed:
        if (widget.canResume) {
          _resumeMedia();
        }
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _pauseMedia();
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  void dispose() {
    _wasDisposed = true;
    _animationController?.dispose();
    _animationController = null;
    widget.flutterStoryController
      ?..removeListener(_storyControllerListener)
      ..dispose();
    _audioDurationSubscriptionStream?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Returns the current story item.
  StoryItem get currentItem => widget.items[_currentIndex];

  /// Returns the configuration for the story view indicator.
  StoryViewIndicatorConfig get storyViewIndicatorConfig =>
      widget.storyViewIndicatorConfig ?? const StoryViewIndicatorConfig();

  /// Listener for the story controller to handle various story actions.
  void _storyControllerListener() {
    final controller = widget.flutterStoryController;
    final storyStatus = controller?.storyStatus;
    final jumpIndex = controller?.jumpIndex;

    if (storyStatus != null) {
      if (storyStatus.isPlay) {
        _resumeMedia();
      } else if (storyStatus.isMute || storyStatus.isUnMute) {
        _toggleMuteUnMuteMedia();
      } else if (storyStatus.isPause) {
        _pauseMedia();
      } else if (storyStatus.isPrevious) {
        _playPrevious();
      } else if (storyStatus.isNext) {
        _playNext();
      }
    }

    if (jumpIndex != null &&
        jumpIndex >= 0 &&
        jumpIndex < widget.items.length) {
      _currentIndex = jumpIndex - 1;
      _playNext();
    }
  }

  /// Starts the story view.
  void _startStoryView() {
    widget.onStoryChanged?.call(_currentIndex);
    _playMedia();
    if (mounted) {
      setState(() {});
    }
  }

  /// Resets the animation controller and its listeners.
  void _resetAnimation() {
    if (_wasDisposed) return;

    _autoPlay = true;
    _animationController?.reset();
    //_animationController?.forward();
    _animationController
      ?..removeListener(animationListener)
      ..removeStatusListener(animationStatusListener);
  }

  /// Initializes and starts the media playback for the current story item.
  void _playMedia() {}

  /// Resumes the media playback.
  void _resumeMedia() {
    if (_wasDisposed) return;

    _audioPlayer?.play();
    _currentVideoPlayer?.play();
    if (_currentProgressAnimation != null) {
      _animationController?.forward(
        from: _currentProgressAnimation?.value,
      );
    }
  }

  /// Starts the countdown for the story item duration.
  void _startStoryCountdown([bool skipVideo = false]) {
    if (_wasDisposed) return;

    widget.onItemLoaded?.call(_currentIndex);

    if (!skipVideo) {
      _currentVideoPlayer?.addListener(videoListener);
      if (_currentVideoPlayer != null) {
        if (_autoPlay) {
          _currentVideoPlayer?.play();
        }
        return;
      }
    }

    if (currentItem.audioConfig != null) {
      _audioPlayer?.durationFuture?.then((v) {
        _totalAudioDuration = v;
        _animationController ??= AnimationController(
          vsync: this,
        );

        _animationController?.duration = v;

        _currentProgressAnimation =
            Tween<double>(begin: 0, end: 1).animate(_animationController!)
              ..addListener(animationListener)
              ..addStatusListener(animationStatusListener);

        if (_autoPlay) {
          _animationController!.forward();
        }
      });
      _audioDurationSubscriptionStream =
          _audioPlayer?.positionStream.listen(audioPositionListener);
      _audioPlayerStateStream = _audioPlayer?.playerStateStream.listen(
        (event) {
          if (event.playing) {
            if (event.processingState == ProcessingState.buffering) {
              _pauseMedia();
            } else if (event.processingState == ProcessingState.loading) {
              _pauseMedia();
            } else {
              _resumeMedia();
            }
          }
        },
      );
      return;
    }

    _animationController ??= AnimationController(
      vsync: this,
    );

    _animationController?.duration =
        _currentVideoPlayer?.value.duration ?? currentItem.duration;

    _currentProgressAnimation =
        Tween<double>(begin: 0, end: 1).animate(_animationController!)
          ..addListener(animationListener)
          ..addStatusListener(animationStatusListener);

    if (_autoPlay) {
      _animationController!.forward();
    }
  }

  /// Listener for the video player's state changes.
  void videoListener() {
    if (_wasDisposed) return;

    final dur = _currentVideoPlayer?.value.duration.inMilliseconds;
    final pos = _currentVideoPlayer?.value.position.inMilliseconds;

    if (pos == dur) {
      _playNext();
      return;
    }

    if (_currentVideoPlayer?.value.isBuffering ?? false) {
      _animationController?.stop(canceled: false);
    }

    if (_currentVideoPlayer?.value.isPlaying ?? false) {
      if (_currentProgressAnimation != null) {
        _animationController?.forward(from: _currentProgressAnimation?.value);
      }
    }
  }

  void audioPositionListener(Duration position) {
    if (_wasDisposed) return;

    final dur = position.inMilliseconds;
    final pos = _totalAudioDuration?.inMilliseconds;

    if (pos == dur) {
      _playNext();
      return;
    }
  }

  /// Listener for the animation progress.
  void animationListener() {
    if (_wasDisposed) return;

    _currentItemProgress = _animationController?.value ?? 0;
  }

  /// Listener for the animation status.
  void animationStatusListener(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _playNext();
    }
  }

  /// Pauses the media playback.
  void _pauseMedia() {
    if (_wasDisposed) return;

    _audioPlayer?.pause();
    _currentVideoPlayer?.pause();
    _animationController?.stop(canceled: false);
  }

  /// Toggles mute/unmute for the media.
  void _toggleMuteUnMuteMedia() {
    if (!_wasDisposed && _currentVideoPlayer != null) {
      final videoPlayerValue = _currentVideoPlayer!.value;
      if (videoPlayerValue.volume == 1) {
        _currentVideoPlayer!.setVolume(0);
      } else {
        _currentVideoPlayer!.setVolume(1);
      }
    }
  }

  /// Plays the next story item.
  void _playNext() async {
    if (widget.items.length == 1 &&
        _currentVideoPlayer != null &&
        widget.restartOnCompleted) {
      await widget.onCompleted?.call();

      /// In case of story length 1 with video, we won't initialise,
      /// instead we will loop the video
      return;
    }
    if (_currentVideoPlayer != null &&
        _currentIndex != (widget.items.length - 1)) {
      /// Dispose the video player only in case of multiple story
      _currentVideoPlayer?.removeListener(videoListener);
      _currentVideoPlayer?.dispose();
      _currentVideoPlayer = null;
    }

    if (_currentIndex == widget.items.length - 1) {
      await widget.onCompleted?.call();
      if (widget.restartOnCompleted) {
        _currentIndex = 0;
        _resetAnimation();
        _startStoryView();
      }
      if (mounted) {
        setState(() {});
      }
      return;
    }

    _currentIndex = _currentIndex + 1;
    _resetAnimation();
    widget.onStoryChanged?.call(_currentIndex);
    _playMedia();
    if (mounted) {
      setState(() {});
    }
  }

  /// Plays the previous story item.
  void _playPrevious() {
    if (widget.canGoBack) {
      if (_audioPlayer != null) {
        _audioPlayer?.dispose();
        _audioDurationSubscriptionStream?.cancel();
        _audioPlayerStateStream?.cancel();
      }
      if (_currentVideoPlayer != null) {
        _currentVideoPlayer?.removeListener(videoListener);
        _currentVideoPlayer?.dispose();
        _currentVideoPlayer = null;
      }
    }

    if (_currentIndex == 0) {
      _resetAnimation();
      _startStoryCountdown(true);

      if (mounted) {
        setState(() {});
      }
      widget.onPreviousCompleted?.call();
      return;
    }

    _resetAnimation();
    _currentIndex = _currentIndex - 1;
    widget.onStoryChanged?.call(_currentIndex);
    _playMedia();
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Stack(
      children: [
        if (currentItem.thumbnail != null) ...{
          currentItem.thumbnail!,
        },
        if (currentItem.storyItemType.isCustom &&
            currentItem.customWidget != null) ...{
          Positioned.fill(
            child: StoryCustomWidgetWrapper(
              key: ValueKey('$_currentIndex'),
              builder: (audioPlayer) {
                return currentItem.customWidget!(
                        widget.flutterStoryController, audioPlayer) ??
                    const SizedBox.shrink();
              },
              storyItem: currentItem,
              onLoaded: () {
                _startStoryCountdown();
              },
              onAudioLoaded: (audioPlayer) {
                _audioPlayer = audioPlayer;
                _startStoryCountdown();
              },
            ),
          ),
        },
        if (currentItem.storyItemType.isImage) ...{
          Positioned.fill(
            child: ImageStoryView(
              key: ValueKey('$_currentIndex'),
              storyItem: currentItem,
              onImageLoaded: (isLoaded) {
                _startStoryCountdown();
              },
              onAudioLoaded: (audioPlayer) {
                _audioPlayer = audioPlayer;
                _startStoryCountdown();
              },
            ),
          ),
        },
        if (currentItem.storyItemType.isVideo) ...{
          Positioned.fill(
            child: VideoStoryView(
              storyItem: currentItem,
              key: ValueKey('$_currentIndex'),
              looping: widget.items.length == 1 && widget.restartOnCompleted,
              onVideoLoad: (videoPlayer) {
                _currentVideoPlayer = videoPlayer;
                widget.onVideoLoad?.call(videoPlayer);
                _startStoryCountdown();
                if (mounted) {
                  setState(() {});
                }
              },
            ),
          ),
        },
        if (currentItem.storyItemType.isWeb) ...{
          Positioned.fill(
            child: WebStoryView(
              storyItem: currentItem,
              key: ValueKey('$_currentIndex'),
              onWebViewLoaded: (controller, loaded) {
                if (loaded) {
                  _startStoryCountdown();
                }
                currentItem.webConfig?.onWebViewLoaded
                    ?.call(controller, loaded);
              },
            ),
          ),
        },
        if (currentItem.storyItemType.isText) ...{
          Positioned.fill(
            child: TextStoryView(
              storyItem: currentItem,
              key: ValueKey('$_currentIndex'),
              onTextStoryLoaded: (loaded) {
                _startStoryCountdown();
              },
              onAudioLoaded: (audioPlayer) {
                _audioPlayer = audioPlayer;
                _startStoryCountdown();
              },
            ),
          ),
        },
        Align(
          alignment: storyViewIndicatorConfig.alignment,
          child: Padding(
            padding: storyViewIndicatorConfig.margin,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _currentVideoPlayer != null
                    ? SmoothVideoProgress(
                        controller: _currentVideoPlayer!,
                        builder: (context, progress, duration, child) {
                          return StoryViewIndicator(
                            currentIndex: _currentIndex,
                            currentItemAnimatedValue: progress.inMilliseconds /
                                duration.inMilliseconds,
                            totalItems: widget.items.length,
                            storyViewIndicatorConfig: storyViewIndicatorConfig,
                          );
                        })
                    : _animationController != null
                        ? AnimatedBuilder(
                            animation: _animationController!,
                            builder: (context, child) => StoryViewIndicator(
                              currentIndex: _currentIndex,
                              currentItemAnimatedValue: _currentItemProgress,
                              totalItems: widget.items.length,
                              storyViewIndicatorConfig:
                                  storyViewIndicatorConfig,
                            ),
                          )
                        : StoryViewIndicator(
                            currentIndex: _currentIndex,
                            currentItemAnimatedValue: _currentItemProgress,
                            totalItems: widget.items.length,
                            storyViewIndicatorConfig: storyViewIndicatorConfig,
                          ),
              ],
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: size.width * .2,
            height: size.height,
            child: GestureDetector(
              onTap: _onTapLeft,
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: size.width * .2,
            height: size.height,
            child: GestureDetector(
              onTap: _onTapRight,
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: GestureDetector(
              key: ValueKey('$_currentIndex'),
              onLongPressDown: (details) {
                _pauseMedia();
              },
              onLongPressUp: () {
                _resumeMedia();
              },
              onLongPressEnd: (details) {
                _resumeMedia();
              },
              onLongPressCancel: () {
                _resumeMedia();
              },
              onVerticalDragStart: widget.onSlideStart?.call,
              onVerticalDragUpdate: widget.onSlideDown?.call,
            ),
          ),
        ),
        if (widget.headerWidget != null) ...{
          Align(
            alignment: Alignment.topCenter,
            child: SafeArea(
                bottom: storyViewIndicatorConfig.enableBottomSafeArea,
                top: storyViewIndicatorConfig.enableTopSafeArea,
                child: widget.headerWidget!),
          ),
        },
        if (widget.footerWidget != null) ...{
          Align(
            alignment: Alignment.bottomCenter,
            child: widget.footerWidget!,
          ),
        },
      ],
    );
  }

  void _onTapLeft() {
    if (Directionality.of(context) == TextDirection.ltr) {
      _playPrevious();
    } else {
      _playNext();
    }
  }

  void _onTapRight() {
    if (Directionality.of(context) == TextDirection.ltr) {
      _playNext();
    } else {
      _playPrevious();
    }
  }
}
