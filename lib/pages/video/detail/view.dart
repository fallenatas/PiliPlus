import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:PiliPalaX/common/constants.dart';
import 'package:PiliPalaX/common/widgets/icon_button.dart';
import 'package:PiliPalaX/common/widgets/list_sheet.dart';
import 'package:PiliPalaX/common/widgets/segment_progress_bar.dart';
import 'package:PiliPalaX/http/loading_state.dart';
import 'package:PiliPalaX/models/bangumi/info.dart';
import 'package:PiliPalaX/models/common/reply_type.dart';
import 'package:PiliPalaX/pages/bangumi/introduction/widgets/intro_detail.dart'
    as bangumi;
import 'package:PiliPalaX/pages/video/detail/introduction/widgets/intro_detail.dart'
    as video;
import 'package:PiliPalaX/pages/video/detail/introduction/widgets/page.dart';
import 'package:PiliPalaX/pages/video/detail/introduction/widgets/season.dart';
import 'package:PiliPalaX/pages/video/detail/member/horizontal_member_page.dart';
import 'package:PiliPalaX/pages/video/detail/reply_reply/view.dart';
import 'package:PiliPalaX/pages/video/detail/widgets/ai_detail.dart';
import 'package:PiliPalaX/utils/extension.dart';
import 'package:PiliPalaX/utils/global_data.dart';
import 'package:PiliPalaX/utils/id_utils.dart';
import 'package:PiliPalaX/utils/utils.dart';
import 'package:auto_orientation/auto_orientation.dart';
import 'package:easy_debounce/easy_throttle.dart';
import 'package:floating/floating.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_svg/svg.dart';
import 'package:get/get.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:nil/nil.dart';
import 'package:PiliPalaX/common/widgets/network_img_layer.dart';
import 'package:PiliPalaX/http/user.dart';
import 'package:PiliPalaX/models/common/search_type.dart';
import 'package:PiliPalaX/pages/bangumi/introduction/index.dart';
import 'package:PiliPalaX/pages/danmaku/view.dart';
import 'package:PiliPalaX/pages/video/detail/reply/index.dart';
import 'package:PiliPalaX/pages/video/detail/controller.dart';
import 'package:PiliPalaX/pages/video/detail/introduction/index.dart';
import 'package:PiliPalaX/pages/video/detail/related/index.dart';
import 'package:PiliPalaX/plugin/pl_player/index.dart';
import 'package:PiliPalaX/plugin/pl_player/models/play_repeat.dart';
import 'package:PiliPalaX/services/service_locator.dart';
import 'package:PiliPalaX/utils/storage.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../../../services/shutdown_timer_service.dart';
import 'widgets/header_control.dart';

class VideoDetailPage extends StatefulWidget {
  const VideoDetailPage({super.key});

  @override
  State<VideoDetailPage> createState() => _VideoDetailPageState();
  static final RouteObserver<PageRoute> routeObserver =
      RouteObserver<PageRoute>();
}

class _VideoDetailPageState extends State<VideoDetailPage>
    with TickerProviderStateMixin, RouteAware, WidgetsBindingObserver {
  late VideoDetailController videoDetailController;
  late VideoReplyController _videoReplyController;
  PlPlayerController? plPlayerController;
  late StreamController<double> appbarStream;
  late VideoIntroController videoIntroController;
  late BangumiIntroController bangumiIntroController;
  late final _introController = ScrollController();
  late String heroTag;

  PlayerStatus playerStatus = PlayerStatus.playing;
  double doubleOffset = 0;

  late Future _futureBuilderFuture;
  // 自动退出全屏
  late bool autoExitFullscreen;
  late bool autoPlayEnable;
  late bool horizontalScreen;
  late bool enableVerticalExpand;
  late bool autoPiP;
  late bool pipNoDanmaku;
  late bool removeSafeArea;
  // late bool showStatusBarBackgroundColor;
  final Floating floating = Floating();
  // 生命周期监听
  // late final AppLifecycleListener _lifecycleListener;
  bool isShowing = true;
  late final MethodChannel onUserLeaveHintListener;
  // StreamSubscription<Duration>? _bufferedListener;
  bool get isFullScreen => plPlayerController?.isFullScreen.value ?? false;

  bool get _shouldShowSeasonPanel =>
      (videoIntroController.videoDetail.value.ugcSeason != null ||
          ((videoIntroController.videoDetail.value.pages?.length ?? 0) > 1)) &&
      context.orientation == Orientation.landscape &&
      videoDetailController.horizontalSeasonPanel;

  StreamSubscription? _listenerDetail;
  StreamSubscription? _listenerLoadingState;
  StreamSubscription? _listenerCid;

  Box get setting => GStorage.setting;

  @override
  void initState() {
    super.initState();

    PlPlayerController.setPlayCallBack(playCallBack);
    if (Get.arguments != null && Get.arguments['heroTag'] != null) {
      heroTag = Get.arguments['heroTag'];
    }
    videoDetailController = Get.put(VideoDetailController(), tag: heroTag);

    if (videoDetailController.showReply) {
      _videoReplyController = Get.put(
          VideoReplyController(videoDetailController.oid.value, '0', '1'),
          tag: heroTag);
    }
    videoIntroController = Get.put(VideoIntroController(), tag: heroTag);
    _listenerDetail = videoIntroController.videoDetail.listen((value) {
      if (!context.mounted) return;
      videoPlayerServiceHandler.onVideoDetailChange(
          value, videoDetailController.cid.value);
    });
    if (videoDetailController.videoType == SearchType.media_bangumi) {
      bangumiIntroController = Get.put(BangumiIntroController(), tag: heroTag);
      _listenerLoadingState =
          bangumiIntroController.loadingState.listen((value) {
        if (!context.mounted) return;
        if (value is Success) {
          videoPlayerServiceHandler.onVideoDetailChange(
            value.response,
            videoDetailController.cid.value,
          );
        }
      });
      _listenerCid = videoDetailController.cid.listen((p0) {
        if (!context.mounted) return;
        if (bangumiIntroController.loadingState.value is Success) {
          videoPlayerServiceHandler.onVideoDetailChange(
            (bangumiIntroController.loadingState.value as Success).response,
            p0,
          );
        }
      });
    }
    autoExitFullscreen =
        setting.get(SettingBoxKey.enableAutoExit, defaultValue: true);
    horizontalScreen =
        setting.get(SettingBoxKey.horizontalScreen, defaultValue: false);
    autoPlayEnable =
        setting.get(SettingBoxKey.autoPlayEnable, defaultValue: false);
    autoPiP = setting.get(SettingBoxKey.autoPiP, defaultValue: false);
    pipNoDanmaku = setting.get(SettingBoxKey.pipNoDanmaku, defaultValue: false);
    enableVerticalExpand =
        setting.get(SettingBoxKey.enableVerticalExpand, defaultValue: false);
    removeSafeArea = setting.get(SettingBoxKey.videoPlayerRemoveSafeArea,
        defaultValue: false);
    // showStatusBarBackgroundColor = setting.get(
    //     SettingBoxKey.videoPlayerShowStatusBarBackgroundColor,
    //     defaultValue: false);
    if (removeSafeArea) hideStatusBar();
    videoSourceInit();
    appbarStreamListen();
    // lifecycleListener();
    autoScreen();
    onUserLeaveHintListener = const MethodChannel("onUserLeaveHint");
    onUserLeaveHintListener.setMethodCallHandler((call) async {
      if (call.method == 'onUserLeaveHint') {
        if (autoPiP &&
            plPlayerController != null &&
            playerStatus == PlayerStatus.playing) {
          autoEnterPip();
        }
      }
    });
    // _animationController = AnimationController(
    //   vsync: this,
    //   duration: const Duration(milliseconds: 300),
    // );
    // _animation = Tween<double>(
    //   begin: MediaQuery.of(context).orientation == Orientation.landscape
    //       ? context.height
    //       : ((enableVerticalExpand &&
    //               plPlayerController?.direction.value == 'vertical')
    //           ? context.width * 5 / 4
    //           : context.width * 9 / 16),
    //   end: 0,
    // ).animate(_animationController);
    WidgetsBinding.instance.addObserver(this);
  }

  // 获取视频资源，初始化播放器
  Future<void> videoSourceInit() async {
    _futureBuilderFuture = videoDetailController.queryVideoUrl();
    if (videoDetailController.showReply) {
      _videoReplyController.queryData();
    }
    if (videoDetailController.autoPlay.value) {
      plPlayerController = videoDetailController.plPlayerController;
      plPlayerController!.addStatusLister(playerListener);
      plPlayerController!.addPositionListener(positionListener);
      await plPlayerController!.autoEnterFullscreen();
    }
  }

  void positionListener(Duration position) {
    if (position.inSeconds != videoDetailController.defaultST.inSeconds) {
      videoDetailController.defaultST = position;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      videoIntroController.startTimer();
      videoDetailController.plPlayerController.showDanmaku = true;
    } else if (state == AppLifecycleState.paused) {
      videoIntroController.canelTimer();
      videoDetailController.plPlayerController.showDanmaku = false;
    }
  }

  void playCallBack() {
    plPlayerController?.play();
  }

  // 流
  appbarStreamListen() {
    appbarStream = StreamController<double>();
  }

  // 播放器状态监听
  void playerListener(PlayerStatus? status) async {
    playerStatus = status!;
    if (status == PlayerStatus.completed) {
      shutdownTimerService.handleWaitingFinished();
      bool notExitFlag = false;

      /// 顺序播放 列表循环
      if (videoDetailController.isPlayAll) {
        notExitFlag = videoIntroController.nextPlay();
      } else if (plPlayerController!.playRepeat != PlayRepeat.pause &&
          plPlayerController!.playRepeat != PlayRepeat.singleCycle) {
        if (videoDetailController.videoType == SearchType.video) {
          notExitFlag = videoIntroController.nextPlay();
        } else if (videoDetailController.videoType ==
            SearchType.media_bangumi) {
          notExitFlag = bangumiIntroController.nextPlay();
        }
      }

      /// 单个循环
      if (plPlayerController!.playRepeat == PlayRepeat.singleCycle) {
        notExitFlag = true;
        plPlayerController!.play(repeat: true);
      }

      // 结束播放退出全屏
      if (!notExitFlag && autoExitFullscreen) {
        plPlayerController!.triggerFullScreen(status: false);
        if (plPlayerController!.doubleSpeedStatus.value) {
          plPlayerController!.setDoubleSpeedStatus(false);
        }
        if (plPlayerController!.controlsLock.value) {
          plPlayerController!.onLockControl(false);
        }
      }
      // 播放完展示控制栏
      if (videoDetailController.floating != null && !notExitFlag) {
        PiPStatus currentStatus =
            await videoDetailController.floating!.pipStatus;
        if (currentStatus == PiPStatus.disabled) {
          plPlayerController!.onLockControl(false);
        }
      }
    }
  }

  // 继续播放或重新播放
  void continuePlay() async {
    plPlayerController!.play();
  }

  /// 未开启自动播放时触发播放
  Future<void> handlePlay() async {
    if (videoDetailController.videoUrl == null ||
        videoDetailController.audioUrl == null) {
      // SmartDialog.showToast('not initialized');
      debugPrint('not initialized');
      return;
    }
    plPlayerController = videoDetailController.plPlayerController;
    videoDetailController.isShowCover.value = false;
    await videoDetailController.playerInit(autoplay: true);
    plPlayerController!.addStatusLister(playerListener);
    plPlayerController!.addPositionListener(positionListener);
    await plPlayerController!.autoEnterFullscreen();
    videoDetailController.autoPlay.value = true;
  }

  // // 生命周期监听
  // void lifecycleListener() {
  //   _lifecycleListener = AppLifecycleListener(
  //     onResume: () => _handleTransition('resume'),
  //     // 后台
  //     onInactive: () => _handleTransition('inactive'),
  //     // 在Android和iOS端不生效
  //     onHide: () => _handleTransition('hide'),
  //     onShow: () => _handleTransition('show'),
  //     onPause: () => _handleTransition('pause'),
  //     onRestart: () => _handleTransition('restart'),
  //     onDetach: () => _handleTransition('detach'),
  //     // 只作用于桌面端
  //     onExitRequested: () {
  //       ScaffoldMessenger.maybeOf(context)
  //           ?.showSnackBar(const SnackBar(content: Text("拦截应用退出")));
  //       return Future.value(AppExitResponse.cancel);
  //     },
  //   );
  // }

  void _makeHeartBeat() {
    plPlayerController!.makeHeartBeat(
      videoDetailController.defaultST.inSeconds,
      type: 'status',
      isManual: true,
      bvid: videoDetailController.bvid,
      cid: videoDetailController.cid.value,
    );
  }

  @override
  void dispose() {
    _listenerDetail?.cancel();
    _listenerLoadingState?.cancel();
    _listenerCid?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (!Get.previousRoute.startsWith('/video')) {
      ScreenBrightness().resetApplicationScreenBrightness();
      PlPlayerController.setPlayCallBack(null);
    }
    videoDetailController.positionSubscription?.cancel();
    videoIntroController.canelTimer();
    appbarStream.close();
    floating.dispose();
    videoDetailController.floating?.dispose();
    videoIntroController.videoDetail.close();
    videoDetailController.cid.close();
    if (!horizontalScreen) {
      AutoOrientation.portraitUpMode();
    }
    shutdownTimerService.handleWaitingFinished();
    // _bufferedListener?.cancel();
    if (plPlayerController != null) {
      _makeHeartBeat();
      plPlayerController!.removeStatusLister(playerListener);
      plPlayerController!.removePositionListener(positionListener);
      plPlayerController!.dispose();
    } else {
      PlPlayerController.updatePlayCount();
    }
    videoPlayerServiceHandler.onVideoDetailDispose();
    VideoDetailPage.routeObserver.unsubscribe(this);
    // _lifecycleListener.dispose();
    showStatusBar();
    // _animationController.dispose();
    super.dispose();
  }

  @override
  // 离开当前页面时
  void didPushNext() async {
    // _bufferedListener?.cancel();
    if (videoDetailController.imageStatus) {
      return;
    }

    ScreenBrightness().resetApplicationScreenBrightness();

    videoDetailController.positionSubscription?.cancel();
    videoIntroController.canelTimer();

    videoDetailController.playerStatus =
        plPlayerController?.playerStatus.status.value;

    /// 开启
    // if (setting.get(SettingBoxKey.enableAutoBrightness, defaultValue: true)
    //     as bool) {
    videoDetailController.brightness = plPlayerController?.brightness.value;
    // }
    if (plPlayerController != null) {
      _makeHeartBeat();
      videoDetailController.vttSubtitlesIndex =
          plPlayerController!.vttSubtitlesIndex.value;
      videoDetailController.showVP = plPlayerController!.showVP.value;
      plPlayerController!.removeStatusLister(playerListener);
      plPlayerController!.removePositionListener(positionListener);
      plPlayerController!.pause();
    }
    isShowing = false;
    super.didPushNext();
  }

  @override
  // 返回当前页面时
  void didPopNext() async {
    if (videoDetailController.imageStatus) {
      return;
    }

    isShowing = true;
    PlPlayerController.setPlayCallBack(playCallBack);
    videoIntroController.startTimer();
    if (mounted) {
      if (videoDetailController.brightness != null) {
        plPlayerController
            ?.setCurrBrightness(videoDetailController.brightness!);
        if (videoDetailController.brightness != -1.0) {
          ScreenBrightness().setApplicationScreenBrightness(
              videoDetailController.brightness!);
        } else {
          ScreenBrightness().resetApplicationScreenBrightness();
        }
      } else {
        ScreenBrightness().resetApplicationScreenBrightness();
      }
    }
    super.didPopNext();
    videoDetailController.isFirstTime = false;
    // final bool autoplay = autoPlayEnable;
    videoDetailController.autoPlay.value =
        !videoDetailController.isShowCover.value;
    if (videoDetailController.videoUrl != null) {
      await videoDetailController.playerInit(
        autoplay: videoDetailController.playerStatus == PlayerStatus.playing,
      );
    }

    // if (videoDetailController.playerStatus == PlayerStatus.playing) {
    //   plPlayerController?.play();
    // }

    /// 未开启自动播放时，未播放跳转下一页返回/播放后跳转下一页返回
    // if (autoplay) {
    //   // await Future.delayed(const Duration(milliseconds: 300));
    //   debugPrint(plPlayerController);
    //   if (plPlayerController?.buffered.value == Duration.zero) {
    //     _bufferedListener = plPlayerController?.buffered.listen((p0) {
    //       debugPrint("p0");
    //       debugPrint(p0);
    //       if (p0 > Duration.zero) {
    //         _bufferedListener!.cancel();
    //         plPlayerController?.seekTo(videoDetailController.defaultST);
    //         plPlayerController?.play();
    //       }
    //     });
    //   } else {
    //     plPlayerController?.seekTo(videoDetailController.defaultST);
    //     plPlayerController?.play();
    //   }
    // }
    Future.delayed(const Duration(milliseconds: 600), () {
      AutoOrientation.fullAutoMode();
    });
    plPlayerController?.addStatusLister(playerListener);
    plPlayerController?.addPositionListener(positionListener);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    VideoDetailPage.routeObserver
        .subscribe(this, ModalRoute.of(context)! as PageRoute);
  }

  // void _handleTransition(String name) {
  //   switch (name) {
  //     case 'inactive':
  //       if (plPlayerController != null &&
  //           playerStatus == PlayerStatus.playing) {
  //         autoEnterPip();
  //       }
  //       break;
  //   }
  // }

  void autoEnterPip() {
    final String routePath = Get.currentRoute;

    if (autoPiP && routePath.startsWith('/video')) {
      floating.enable(
        EnableManual(
          aspectRatio: Rational(
            videoDetailController.data.dash!.video!.first.width!,
            videoDetailController.data.dash!.video!.first.height!,
          ),
        ),
      );
    }
  }

  Widget get childWhenDisabled => SafeArea(
        top: !removeSafeArea &&
            MediaQuery.of(context).orientation == Orientation.portrait &&
            isFullScreen,
        bottom: !removeSafeArea &&
            MediaQuery.of(context).orientation == Orientation.portrait &&
            isFullScreen,
        left: false, //!isFullScreen,
        right: false, //!isFullScreen,
        child: Stack(
          children: [
            Scaffold(
              resizeToAvoidBottomInset: false,
              key: videoDetailController.scaffoldKey,
              // backgroundColor: Colors.black,
              appBar: removeSafeArea
                  ? null
                  : AppBar(
                      backgroundColor: Colors.black,
                      // showStatusBarBackgroundColor ? null : Colors.black,
                      toolbarHeight: 0,
                      // systemOverlayStyle: SystemUiOverlayStyle(
                      //   statusBarIconBrightness:
                      //       Theme.of(context).brightness == Brightness.dark ||
                      //               !showStatusBarBackgroundColor
                      //           ? Brightness.light
                      //           : Brightness.dark,
                      //   systemNavigationBarColor: Colors.transparent,
                      // ),
                    ),
              body: Column(
                children: [
                  Obx(
                    () {
                      double videoHeight = context.width * 9 / 16;
                      final double videoWidth = context.width;
                      // debugPrint(videoDetailController.tabCtr.index);
                      if (enableVerticalExpand &&
                          plPlayerController?.direction.value == 'vertical') {
                        videoHeight = context.width;
                      }
                      if (MediaQuery.of(context).orientation ==
                              Orientation.landscape &&
                          !horizontalScreen &&
                          !isFullScreen &&
                          isShowing &&
                          mounted) {
                        hideStatusBar();
                      }
                      if (MediaQuery.of(context).orientation ==
                              Orientation.portrait &&
                          !isFullScreen &&
                          isShowing &&
                          mounted) {
                        if (!removeSafeArea) showStatusBar();
                      }
                      return Container(
                        color: Colors.black,
                        // showStatusBarBackgroundColor ? null : Colors.black,
                        height: MediaQuery.of(context).orientation ==
                                    Orientation.landscape ||
                                isFullScreen
                            ? MediaQuery.sizeOf(context).height -
                                (MediaQuery.of(context).orientation ==
                                            Orientation.landscape ||
                                        removeSafeArea
                                    ? 0
                                    : MediaQuery.of(context).padding.top)
                            : videoHeight,
                        width: context.width,
                        child: PopScope(
                          canPop: !isFullScreen &&
                              (horizontalScreen ||
                                  MediaQuery.of(context).orientation ==
                                      Orientation.portrait),
                          onPopInvokedWithResult: _onPopInvokedWithResult,
                          child: videoPlayer(videoWidth, videoHeight),
                        ),
                      );
                    },
                  ),
                  Expanded(
                    child: Scaffold(
                      key: videoDetailController.childKey,
                      resizeToAvoidBottomInset: false,
                      body: Column(
                        children: [
                          buildTabbar(
                            showReply: videoDetailController.showReply,
                          ),
                          Expanded(
                            child: TabBarView(
                              physics: const ClampingScrollPhysics(),
                              controller: videoDetailController.tabCtr,
                              children: [
                                videoIntro(),
                                if (videoDetailController.showReply)
                                  videoReplyPanel,
                                if (_shouldShowSeasonPanel) seasonPanel,
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget get childWhenDisabledAlmostSquareInner => Obx(
        () {
          if (enableVerticalExpand &&
              plPlayerController?.direction.value == 'vertical') {
            final double videoHeight = context.height -
                (removeSafeArea
                    ? 0
                    : (MediaQuery.of(context).padding.top +
                        MediaQuery.of(context).padding.bottom));
            final double videoWidth = videoHeight * 9 / 16;
            return Row(
              children: [
                SizedBox(
                  height: videoHeight,
                  width: isFullScreen ? context.width : videoWidth,
                  child: PopScope(
                    canPop: !isFullScreen,
                    onPopInvokedWithResult: _onPopInvokedWithResult,
                    child: videoPlayer(videoWidth, videoHeight),
                  ),
                ),
                Expanded(
                  child: Scaffold(
                    key: videoDetailController.childKey,
                    resizeToAvoidBottomInset: false,
                    body: Column(
                      children: [
                        buildTabbar(showReply: videoDetailController.showReply),
                        Expanded(
                          child: TabBarView(
                            physics: const ClampingScrollPhysics(),
                            controller: videoDetailController.tabCtr,
                            children: [
                              videoIntro(),
                              if (videoDetailController.showReply)
                                videoReplyPanel,
                              if (_shouldShowSeasonPanel) seasonPanel,
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }
          final double videoHeight = context.height / 2.5;
          final double videoWidth = context.width;
          return Column(
            children: [
              SizedBox(
                width: videoWidth,
                height: isFullScreen
                    ? context.height -
                        (removeSafeArea
                            ? 0
                            : (MediaQuery.of(context).padding.top +
                                MediaQuery.of(context).padding.bottom))
                    : videoHeight,
                child: PopScope(
                  canPop: !isFullScreen,
                  onPopInvokedWithResult: _onPopInvokedWithResult,
                  child: videoPlayer(videoWidth, videoHeight),
                ),
              ),
              Expanded(
                child: Scaffold(
                  key: videoDetailController.childKey,
                  resizeToAvoidBottomInset: false,
                  body: Column(
                    children: [
                      buildTabbar(
                        needIndicator: false,
                        showReply: videoDetailController.showReply,
                      ),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(child: videoIntro()),
                            if (videoDetailController.showReply)
                              Expanded(child: videoReplyPanel),
                            if (_shouldShowSeasonPanel)
                              Expanded(child: seasonPanel),
                          ],
                        ),
                      )
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      );

  Widget get childWhenDisabledLandscapeInner => Obx(
        () {
          if (enableVerticalExpand &&
              plPlayerController?.direction.value == 'vertical') {
            final double videoHeight = context.height -
                (removeSafeArea ? 0 : MediaQuery.of(context).padding.top);
            final double videoWidth = videoHeight * 9 / 16;
            return Row(
              children: [
                Expanded(child: videoIntro()),
                SizedBox(
                  height: videoHeight,
                  width: isFullScreen ? context.width : videoWidth,
                  child: PopScope(
                    canPop: !isFullScreen,
                    onPopInvokedWithResult: _onPopInvokedWithResult,
                    child: videoPlayer(videoWidth, videoHeight),
                  ),
                ),
                Expanded(
                  child: Expanded(
                    child: Scaffold(
                      key: videoDetailController.childKey,
                      resizeToAvoidBottomInset: false,
                      body: Column(
                        children: [
                          buildTabbar(
                            showIntro: false,
                            showReply: videoDetailController.showReply,
                          ),
                          Expanded(
                            child: TabBarView(
                              controller: videoDetailController.tabCtr,
                              children: [
                                if (videoDetailController.showReply)
                                  videoReplyPanel,
                                if (_shouldShowSeasonPanel) seasonPanel,
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Expanded(
                //   child: TabBarView(
                //     physics: const ClampingScrollPhysics(),
                //     controller: videoDetailController.tabCtr,
                //     children: [
                //       CustomScrollView(
                //         key: const PageStorageKey<String>('简介'),
                //         slivers: [
                //           if (videoDetailController.videoType ==
                //               SearchType.video) ...[
                //             const VideoIntroPanel(),
                //           ] else if (videoDetailController.videoType ==
                //               SearchType.media_bangumi) ...[
                //             Obx(() => BangumiIntroPanel(
                //                 cid: videoDetailController.cid.value)),
                //           ],
                //           SliverToBoxAdapter(
                //             child: Divider(
                //               indent: 12,
                //               endIndent: 12,
                //               color: Theme.of(context).dividerColor.withOpacity(0.06),
                //             ),
                //           ),
                //           const RelatedVideoPanel(),
                //         ],
                //       ),
                //       Obx(
                //             () => VideoReplyPanel(
                //           bvid: videoDetailController.bvid,
                //           oid: videoDetailController.oid.value,
                //         ),
                //       )
                //     ],
                //   ),
                // ),
              ],
            );
          }
          final double videoWidth =
              max(context.height / context.width * 1.04, 1 / 2) * context.width;
          final double videoHeight = videoWidth * 9 / 16;
          return Row(
            children: [
              Column(
                children: [
                  SizedBox(
                    width: isFullScreen ? context.width : videoWidth,
                    height: isFullScreen ? context.height : videoHeight,
                    child: PopScope(
                      canPop: !isFullScreen,
                      onPopInvokedWithResult: _onPopInvokedWithResult,
                      child: videoPlayer(videoWidth, videoHeight),
                    ),
                  ),
                  Offstage(
                    offstage: isFullScreen,
                    child: SizedBox(
                      width: videoWidth,
                      height: context.height -
                          videoHeight -
                          (removeSafeArea
                              ? 0
                              : MediaQuery.of(context).padding.top),
                      child: videoIntro(false),
                    ),
                  ),
                ],
              ),
              Offstage(
                offstage: isFullScreen,
                child: SizedBox(
                  width: (context.width -
                      videoWidth -
                      (removeSafeArea
                          ? 0
                          : (MediaQuery.of(context).padding.left +
                              MediaQuery.of(context).padding.right))),
                  height: context.height -
                      (removeSafeArea ? 0 : MediaQuery.of(context).padding.top),
                  child: Scaffold(
                    key: videoDetailController.childKey,
                    resizeToAvoidBottomInset: false,
                    body: Column(
                      children: [
                        buildTabbar(
                          introText: '相关视频',
                          showIntro: videoDetailController.videoType ==
                                  SearchType.video &&
                              videoDetailController.showRelatedVideo,
                          showReply: videoDetailController.showReply,
                        ),
                        Expanded(
                          child: TabBarView(
                            physics: const ClampingScrollPhysics(),
                            controller: videoDetailController.tabCtr,
                            children: [
                              if (videoDetailController.videoType ==
                                      SearchType.video &&
                                  videoDetailController.showRelatedVideo)
                                CustomScrollView(
                                  controller: _introController,
                                  slivers: [
                                    RelatedVideoPanel(heroTag: heroTag),
                                  ],
                                ),
                              if (videoDetailController.showReply)
                                videoReplyPanel,
                              if (_shouldShowSeasonPanel) seasonPanel,
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            ],
          );
        },
      );

  Widget get childWhenDisabledLandscape => Stack(
        children: [
          Scaffold(
            resizeToAvoidBottomInset: false,
            key: videoDetailController.scaffoldKey,
            // backgroundColor: Colors.black,
            appBar: removeSafeArea
                ? null
                : AppBar(
                    backgroundColor: Colors.black,
                    // showStatusBarBackgroundColor ? null : Colors.black,
                    toolbarHeight: 0,
                    // systemOverlayStyle: SystemUiOverlayStyle(
                    //   statusBarIconBrightness:
                    //       Theme.of(context).brightness == Brightness.dark ||
                    //               !showStatusBarBackgroundColor
                    //           ? Brightness.light
                    //           : Brightness.dark,
                    //   systemNavigationBarColor: Colors.transparent,
                    // ),
                  ),
            body: Container(
              color: Theme.of(context).colorScheme.surface,
              child: SafeArea(
                  left: !removeSafeArea && !isFullScreen,
                  right: !removeSafeArea && !isFullScreen,
                  top: !removeSafeArea,
                  bottom: false, //!removeSafeArea,
                  child: childWhenDisabledLandscapeInner),
            ),
          ),
        ],
      );

  Widget get childWhenDisabledAlmostSquare => Stack(children: [
        Scaffold(
            resizeToAvoidBottomInset: false,
            key: videoDetailController.scaffoldKey,
            // backgroundColor: Colors.black,
            appBar: removeSafeArea
                ? null
                : AppBar(
                    backgroundColor: Colors.black,
                    // showStatusBarBackgroundColor ? null : Colors.black,
                    toolbarHeight: 0,
                    // systemOverlayStyle: SystemUiOverlayStyle(
                    //   statusBarIconBrightness:
                    //       Theme.of(context).brightness == Brightness.dark ||
                    //               !showStatusBarBackgroundColor
                    //           ? Brightness.light
                    //           : Brightness.dark,
                    //   systemNavigationBarColor: Colors.transparent,
                    // ),
                  ),
            body: Container(
                color: Theme.of(context).colorScheme.surface,
                child: SafeArea(
                    left: !removeSafeArea && !isFullScreen,
                    right: !removeSafeArea && !isFullScreen,
                    top: !removeSafeArea,
                    bottom: false, //!removeSafeArea,
                    child: childWhenDisabledAlmostSquareInner)))
      ]);

  Widget get childWhenEnabled => Obx(
        () => !videoDetailController.autoPlay.value
            ? const SizedBox()
            : PLVideoPlayer(
                plPlayerController: plPlayerController!,
                videoIntroController:
                    videoDetailController.videoType == SearchType.video
                        ? videoIntroController
                        : null,
                bangumiIntroController:
                    videoDetailController.videoType == SearchType.media_bangumi
                        ? bangumiIntroController
                        : null,
                headerControl: HeaderControl(
                  controller: plPlayerController,
                  videoDetailCtr: videoDetailController,
                  heroTag: heroTag,
                ),
                danmuWidget: pipNoDanmaku
                    ? null
                    : Obx(
                        () => PlDanmaku(
                          key: Key(videoDetailController.danmakuCid.value
                              .toString()),
                          isPipMode: true,
                          cid: videoDetailController.danmakuCid.value,
                          playerController: plPlayerController!,
                        ),
                      ),
                showEpisodes: showEpisodes,
                showViewPoints: showViewPoints,
              ),
      );

  Widget get manualPlayerWidget => Obx(
        () => Visibility(
          visible: videoDetailController.isShowCover.value &&
              videoDetailController.isEffective.value,
          child: Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: AppBar(
                  primary: false,
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.transparent,
                  // automaticallyImplyLeading: false,
                  // title: Row(
                  //   children: [
                  //     SizedBox(
                  //       width: 42,
                  //       height: 34,
                  //       child: IconButton(
                  //         tooltip: '返回',
                  //         icon: const Icon(
                  //           FontAwesomeIcons.arrowLeft,
                  //           size: 15,
                  //           color: Colors.white,
                  //         ),
                  //         onPressed: Get.back,
                  //       ),
                  //     ),
                  //     SizedBox(
                  //       width: 42,
                  //       height: 34,
                  //       child: IconButton(
                  //         tooltip: '返回主页',
                  //         icon: const Icon(
                  //           FontAwesomeIcons.house,
                  //           size: 15,
                  //           color: Colors.white,
                  //         ),
                  //         onPressed: () {
                  //           Get.until((route) => route.isFirst);
                  //         },
                  //       ),
                  //     ),
                  //   ],
                  // ),
                  actions: [
                    PopupMenuButton<String>(
                      onSelected: (String type) async {
                        switch (type) {
                          case 'later':
                            var res = await UserHttp.toViewLater(
                                bvid: videoDetailController.bvid);
                            SmartDialog.showToast(res['msg']);
                            break;
                          case 'report':
                            if (videoDetailController.userInfo == null) {
                              SmartDialog.showToast('账号未登录');
                            } else {
                              Get.toNamed('/webviewnew', parameters: {
                                'url':
                                    'https://www.bilibili.com/appeal/?avid=${IdUtils.bv2av(videoDetailController.bvid)}&bvid=${videoDetailController.bvid}'
                              });
                            }
                            break;
                        }
                      },
                      itemBuilder: (BuildContext context) =>
                          <PopupMenuEntry<String>>[
                        const PopupMenuItem<String>(
                          value: 'later',
                          child: Text('稍后再看'),
                        ),
                        const PopupMenuItem<String>(
                          value: 'report',
                          child: Text('举报'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 12,
                bottom: 10,
                child: IconButton(
                  tooltip: '播放',
                  onPressed: handlePlay,
                  icon: Image.asset(
                    'assets/images/play.png',
                    width: 60,
                    height: 60,
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Widget get plPlayer => FutureBuilder(
        future: _futureBuilderFuture,
        builder: (BuildContext context, AsyncSnapshot snapshot) {
          if (snapshot.hasData && snapshot.data['status']) {
            return Obx(
              () => !videoDetailController.autoPlay.value ||
                      plPlayerController == null ||
                      plPlayerController!.videoController == null
                  ? nil
                  : PLVideoPlayer(
                      plPlayerController: plPlayerController!,
                      videoIntroController:
                          videoDetailController.videoType == SearchType.video
                              ? videoIntroController
                              : null,
                      bangumiIntroController: videoDetailController.videoType ==
                              SearchType.media_bangumi
                          ? bangumiIntroController
                          : null,
                      headerControl: videoDetailController.headerControl,
                      danmuWidget: Obx(
                        () => PlDanmaku(
                          key: Key(videoDetailController.danmakuCid.value
                              .toString()),
                          cid: videoDetailController.danmakuCid.value,
                          playerController: plPlayerController!,
                        ),
                      ),
                      showEpisodes: showEpisodes,
                      showViewPoints: showViewPoints,
                    ),
            );
          } else {
            return const SizedBox();
          }
        },
      );

  Widget autoChoose(Widget childWhenDisabled) {
    if (Platform.isAndroid) {
      return PiPSwitcher(
        childWhenDisabled: childWhenDisabled,
        childWhenEnabled: childWhenEnabled,
        floating: floating,
      );
    }
    return childWhenDisabled;
  }

  @override
  Widget build(BuildContext context) {
    if (!horizontalScreen) {
      return autoChoose(childWhenDisabled);
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // if (!isShowing) {
        //   return ColoredBox(color: Theme.of(context).colorScheme.surface);
        // }
        if (constraints.maxWidth > constraints.maxHeight * 1.25) {
//             hideStatusBar();
//             videoDetailController.hiddenReplyReplyPanel();
          return autoChoose(childWhenDisabledLandscape);
        } else if (constraints.maxWidth * (9 / 16) <
            (2 / 5) * constraints.maxHeight) {
          // if (!isFullScreen) {
          //   if (!removeSafeArea) showStatusBar();
          // }
          return autoChoose(childWhenDisabled);
        } else {
          // if (!isFullScreen) {
          //   if (!removeSafeArea) showStatusBar();
          // }
          return autoChoose(childWhenDisabledAlmostSquare);
        }
        //
        // final Orientation orientation =
        //     constraints.maxWidth > constraints.maxHeight * 1.25
        //         ? Orientation.landscape
        //         : Orientation.portrait;
        // if (orientation == Orientation.landscape) {
        //   if (!horizontalScreen) {
        //     hideStatusBar();
        //     videoDetailController.hiddenReplyReplyPanel();
        //   }
        // } else {
        //   if (!isFullScreen) {
        //     showStatusBar();
        //   }
        // }
        // if (Platform.isAndroid) {
        //   return PiPSwitcher(
        //     childWhenDisabled:
        //         !horizontalScreen || orientation == Orientation.portrait
        //             ? childWhenDisabled
        //             : childWhenDisabledLandscape,
        //     childWhenEnabled: childWhenEnabled,
        //     floating: floating,
        //   );
        // }
        // return !horizontalScreen || orientation == Orientation.portrait
        //     ? childWhenDisabled
        //     : childWhenDisabledLandscape;
      },
    );
  }

  Widget buildTabbar({
    bool needIndicator = true,
    String introText = '简介',
    bool showIntro = true,
    bool showReply = true,
  }) {
    List<String> tabs = [
      if (showIntro) introText,
      if (showReply) '评论',
      if (_shouldShowSeasonPanel) '播放列表',
    ];
    if (videoDetailController.tabCtr.length != tabs.length) {
      videoDetailController.tabCtr = TabController(
        vsync: this,
        length: tabs.length,
        initialIndex: tabs.length > videoDetailController.tabCtr.length
            ? videoDetailController.tabCtr.index
            : 0,
      );
    }

    Widget tabbar() => TabBar(
          labelColor: needIndicator.not || tabs.length == 1
              ? Theme.of(context).colorScheme.onSurface
              : null,
          indicatorColor:
              needIndicator.not || tabs.length == 1 ? Colors.transparent : null,
          padding: EdgeInsets.zero,
          controller: videoDetailController.tabCtr,
          labelStyle: const TextStyle(fontSize: 13),
          labelPadding:
              const EdgeInsets.symmetric(horizontal: 10.0), // 设置每个标签的宽度
          dividerColor: Colors.transparent,
          onTap: (value) {
            void animToTop() {
              String text = tabs[value];
              if (text == '简介' || text == '相关视频') {
                _introController.animToTop();
              } else if (text.startsWith('评论')) {
                _videoReplyController.animateToTop();
              }
            }

            if (needIndicator.not || tabs.length == 1) {
              animToTop();
            } else if (videoDetailController.tabCtr.indexIsChanging.not) {
              animToTop();
            }
          },
          tabs: tabs.map((text) {
            if (text == '评论') {
              return Tab(
                text:
                    '评论${_videoReplyController.count.value == -1 ? '' : ' ${_videoReplyController.count.value}'}',
              );
            } else {
              return Tab(text: text);
            }
          }).toList(),
        );

    return Container(
      width: double.infinity,
      height: 45,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            width: 1,
            color: Theme.of(context).dividerColor.withOpacity(0.1),
          ),
        ),
      ),
      child: Material(
        child: Row(
          children: [
            if (tabs.isEmpty)
              const Spacer()
            else
              Flexible(
                flex: tabs.length == 3 ? 2 : 1,
                child: showReply ? Obx(() => tabbar()) : tabbar(),
              ),
            Flexible(
              flex: 1,
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SizedBox(
                      height: 32,
                      child: TextButton(
                        style: ButtonStyle(
                          padding: WidgetStateProperty.all(EdgeInsets.zero),
                        ),
                        onPressed: videoDetailController.showShootDanmakuSheet,
                        child: Text(
                          '发弹幕',
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 38,
                      height: 38,
                      child: Obx(
                        () => IconButton(
                          onPressed: () {
                            videoDetailController
                                    .plPlayerController.isOpenDanmu.value =
                                !videoDetailController
                                    .plPlayerController.isOpenDanmu.value;
                            setting.put(
                                SettingBoxKey.enableShowDanmaku,
                                videoDetailController
                                    .plPlayerController.isOpenDanmu.value);
                          },
                          icon: SvgPicture.asset(
                            videoDetailController
                                    .plPlayerController.isOpenDanmu.value
                                ? 'assets/images/video/danmu_open.svg'
                                : 'assets/images/video/danmu_close.svg',
                            // ignore: deprecated_member_use
                            color: videoDetailController
                                    .plPlayerController.isOpenDanmu.value
                                ? Theme.of(context).colorScheme.secondary
                                : Theme.of(context).colorScheme.outline,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget videoPlayer(double videoWidth, double videoHeight) => Stack(
        children: [
          if (isShowing) plPlayer,

          /// 关闭自动播放时 手动播放
          if (!videoDetailController.autoPlay.value) ...[
            Obx(
              () => Visibility(
                visible: videoDetailController.isShowCover.value,
                child: Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: handlePlay,
                    child: Obx(
                      () => NetworkImgLayer(
                        type: 'emote',
                        src: videoDetailController.videoItem['pic'],
                        width: videoWidth,
                        height: videoHeight,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            manualPlayerWidget,
          ]
        ],
      );

  Widget videoIntro([bool needRelated = true]) {
    Widget introPanel() => CustomScrollView(
          controller: needRelated ? _introController : null,
          slivers: [
            if (videoDetailController.videoType == SearchType.video) ...[
              VideoIntroPanel(
                heroTag: heroTag,
                showAiBottomSheet: showAiBottomSheet,
                showIntroDetail: showIntroDetail,
                showEpisodes: showEpisodes,
                onShowMemberPage: onShowMemberPage,
              ),
              if (needRelated && videoDetailController.showRelatedVideo) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(
                      top: StyleString.safeSpace,
                    ),
                    child: Divider(
                      height: 1,
                      indent: 12,
                      endIndent: 12,
                      color: Theme.of(context).dividerColor.withOpacity(0.06),
                    ),
                  ),
                ),
                RelatedVideoPanel(heroTag: heroTag),
              ],
            ] else if (videoDetailController.videoType ==
                SearchType.media_bangumi)
              Obx(
                () => BangumiIntroPanel(
                  heroTag: heroTag,
                  cid: videoDetailController.cid.value,
                  showEpisodes: showEpisodes,
                  showIntroDetail: showIntroDetail,
                ),
              ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: MediaQuery.paddingOf(context).bottom +
                    (videoDetailController.isPlayAll &&
                            MediaQuery.orientationOf(context) ==
                                Orientation.landscape
                        ? 75
                        : 0),
              ),
            )
          ],
        );
    if (videoDetailController.isPlayAll) {
      return Stack(
        children: [
          introPanel(),
          Obx(
            () => AnimatedPositioned(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOut,
              left: 12,
              right: 12,
              bottom: MediaQuery.of(context).padding.bottom + 12,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: videoDetailController.showMediaListPanel,
                  borderRadius: const BorderRadius.all(Radius.circular(14)),
                  child: Container(
                    height: 54,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .secondaryContainer
                          .withOpacity(0.95),
                      borderRadius: const BorderRadius.all(Radius.circular(14)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.playlist_play, size: 24),
                        const SizedBox(width: 10),
                        Text(
                          videoDetailController.watchLaterTitle.value,
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSecondaryContainer,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const Spacer(),
                        const Icon(Icons.keyboard_arrow_up_rounded, size: 26),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    } else {
      return introPanel();
    }
  }

  Widget get seasonPanel => Column(
        children: [
          if ((videoIntroController.videoDetail.value.pages?.length ?? 0) > 1)
            Obx(
              () => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: PagesPanel(
                  heroTag: heroTag,
                  pages: videoIntroController.videoDetail.value.pages!,
                  cid: videoIntroController.lastPlayCid.value,
                  bvid: videoIntroController.bvid,
                  changeFuc: videoIntroController.changeSeasonOrbangu,
                  showEpisodes: showEpisodes,
                ),
              ),
            ),
          if (videoIntroController.videoDetail.value.ugcSeason != null) ...[
            if ((videoIntroController.videoDetail.value.pages?.length ?? 0) > 1)
              Divider(
                height: 1,
                color: Theme.of(context).colorScheme.outline.withOpacity(0.1),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SeasonPanel(
                heroTag: heroTag,
                onTap: false,
                ugcSeason: videoIntroController.videoDetail.value.ugcSeason!,
                cid: videoIntroController.lastPlayCid.value != 0
                    ? (videoIntroController
                                .videoDetail.value.pages?.isNotEmpty ==
                            true
                        ? videoIntroController
                            .videoDetail.value.pages!.first.cid
                        : videoIntroController.lastPlayCid.value)
                    : videoIntroController.videoDetail.value.pages!.first.cid,
                changeFuc: videoIntroController.changeSeasonOrbangu,
                showEpisodes: showEpisodes,
                pages: videoIntroController.videoDetail.value.pages,
              ),
            ),
            Expanded(
              child: Obx(
                () => ListSheetContent(
                  index: videoDetailController.seasonIndex.value,
                  season: videoIntroController.videoDetail.value.ugcSeason!,
                  episodes: videoDetailController.episodes,
                  bvid: videoDetailController.bvid,
                  aid: IdUtils.bv2av(videoDetailController.bvid),
                  currentCid: videoDetailController.seasonCid,
                  changeFucCall: videoDetailController.videoType ==
                          SearchType.media_bangumi
                      ? bangumiIntroController.changeSeasonOrbangu
                      : videoIntroController.changeSeasonOrbangu,
                ),
              ),
            ),
          ],
        ],
      );

  Widget get videoReplyPanel => Obx(
        () => VideoReplyPanel(
          bvid: videoDetailController.bvid,
          oid: videoDetailController.oid.value,
          heroTag: heroTag,
          replyReply: replyReply,
          onViewImage: videoDetailController.onViewImage,
          onDismissed: videoDetailController.onDismissed,
        ),
      );

  // 展示二级回复
  void replyReply(replyItem, id, isTop) {
    EasyThrottle.throttle('replyReply', const Duration(milliseconds: 500), () {
      int oid = replyItem.oid.toInt();
      int rpid = GlobalData().grpcReply ? replyItem.id.toInt() : replyItem.rpid;
      videoDetailController.childKey.currentState?.showBottomSheet(
        (context) => VideoReplyReplyPanel(
          id: id,
          oid: oid,
          rpid: rpid,
          firstFloor: replyItem,
          replyType: ReplyType.video,
          source: 'videoDetail',
          isTop: isTop ?? false,
          onViewImage: videoDetailController.onViewImage,
          onDismissed: videoDetailController.onDismissed,
        ),
      );
    });
  }

  // ai总结
  showAiBottomSheet() {
    videoDetailController.childKey.currentState?.showBottomSheet(
      enableDrag: true,
      (context) => AiDetail(modelResult: videoIntroController.modelResult),
    );
  }

  showIntroDetail(videoDetail, videoTags) {
    videoDetailController.childKey.currentState?.showBottomSheet(
      enableDrag: true,
      (context) => videoDetail is BangumiInfoModel
          ? bangumi.IntroDetail(
              bangumiDetail: videoDetail,
              videoTags: videoTags,
            )
          : video.IntroDetail(
              videoDetail: videoDetail,
              videoTags: videoTags,
            ),
    );
  }

  showEpisodes(index, season, episodes, bvid, aid, cid) {
    Widget listSheetContent() => ListSheetContent(
          index: index,
          season: season,
          episodes: episodes,
          bvid: bvid,
          aid: aid,
          currentCid: cid,
          changeFucCall:
              videoDetailController.videoType == SearchType.media_bangumi
                  ? bangumiIntroController.changeSeasonOrbangu
                  : videoIntroController.changeSeasonOrbangu,
          onClose: () {
            if (videoDetailController.bsController != null) {
              videoDetailController.bsController!.close();
              videoDetailController.bsController = null;
            } else {
              Get.back();
            }
          },
        );
    if (isFullScreen) {
      videoDetailController.bsController =
          videoDetailController.scaffoldKey.currentState?.showBottomSheet(
        (context) => listSheetContent(),
      );
    } else {
      videoDetailController.childKey.currentState?.showBottomSheet(
        (context) => listSheetContent(),
      );
    }
  }

  void showViewPoints() {
    Widget listSheetContent(context, [bool isFS = false]) {
      int currentIndex = -1;
      return StatefulBuilder(
        builder: (context, setState) => SizedBox(
          height: isFS ? Utils.getSheetHeight(context) : null,
          child: Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: false,
              titleSpacing: 16,
              title: Text('分段信息'),
              actions: [
                Text(
                  '分段进度条',
                  style: TextStyle(fontSize: 16),
                ),
                Obx(
                  () => Transform.scale(
                    alignment: Alignment.centerLeft,
                    scale: 0.8,
                    child: Switch(
                      thumbIcon:
                          WidgetStateProperty.resolveWith<Icon?>((states) {
                        if (states.isNotEmpty &&
                            states.first == WidgetState.selected) {
                          return const Icon(Icons.done);
                        }
                        return null;
                      }),
                      value:
                          videoDetailController.plPlayerController.showVP.value,
                      onChanged: (value) {
                        videoDetailController.plPlayerController.showVP.value =
                            value;
                      },
                    ),
                  ),
                ),
                iconButton(
                  context: context,
                  size: 30,
                  icon: Icons.clear,
                  tooltip: '关闭',
                  onPressed: () {
                    if (videoDetailController.bsController != null) {
                      videoDetailController.bsController!.close();
                      videoDetailController.bsController = null;
                    } else {
                      Get.back();
                    }
                  },
                ),
                const SizedBox(width: 16),
              ],
            ),
            body: SingleChildScrollView(
              child: Column(
                children: [
                  ...List.generate(
                      videoDetailController.viewPointList.length * 2 - 1,
                      (rawIndex) {
                    if (rawIndex % 2 == 1) {
                      return Divider(
                        height: 1,
                        color: Theme.of(context).dividerColor.withOpacity(0.1),
                      );
                    }
                    int index = rawIndex ~/ 2;
                    Segment segment =
                        videoDetailController.viewPointList[index];
                    if (currentIndex == -1 &&
                        segment.from != null &&
                        segment.to != null) {
                      if (videoDetailController
                                  .plPlayerController.positionSeconds.value >=
                              segment.from! &&
                          videoDetailController
                                  .plPlayerController.positionSeconds.value <
                              segment.to!) {
                        currentIndex = index;
                      }
                    }
                    return ListTile(
                      dense: true,
                      onTap: segment.from != null
                          ? () {
                              currentIndex = index;
                              plPlayerController?.danmakuController?.clear();
                              plPlayerController?.videoPlayerController
                                  ?.seek(Duration(seconds: segment.from!));
                              if (videoDetailController.bsController != null) {
                                videoDetailController.bsController!.close();
                                videoDetailController.bsController = null;
                              } else {
                                setState(() {});
                              }
                            }
                          : null,
                      leading: segment.url?.isNotEmpty == true
                          ? Container(
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              decoration: currentIndex == index
                                  ? BoxDecoration(
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        width: 1.8,
                                        strokeAlign:
                                            BorderSide.strokeAlignOutside,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                      ),
                                    )
                                  : null,
                              child: LayoutBuilder(
                                builder: (context, constraints) =>
                                    NetworkImgLayer(
                                  radius: 6,
                                  src: segment.url,
                                  width: constraints.maxHeight *
                                      StyleString.aspectRatio,
                                  height: constraints.maxHeight,
                                ),
                              ),
                            )
                          : null,
                      title: Text(
                        segment.title ?? '',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              currentIndex == index ? FontWeight.bold : null,
                          color: currentIndex == index
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                      ),
                      subtitle: Text(
                        '${segment.from != null ? Utils.timeFormat(segment.from) : ''} - ${segment.to != null ? Utils.timeFormat(segment.to) : ''}',
                        style: TextStyle(
                          fontSize: 13,
                          color: currentIndex == index
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    );
                  }),
                  SizedBox(height: 25 + MediaQuery.paddingOf(context).bottom),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (isFullScreen) {
      videoDetailController.bsController =
          videoDetailController.scaffoldKey.currentState?.showBottomSheet(
        (context) => listSheetContent(context, true),
      );
    } else {
      videoDetailController.childKey.currentState?.showBottomSheet(
        (context) => listSheetContent(context),
      );
    }
  }

  void _onPopInvokedWithResult(didPop, result) {
    if (videoDetailController.bsController != null) {
      videoDetailController.bsController!.close();
      videoDetailController.bsController = null;
      return;
    }
    if (plPlayerController?.controlsLock.value == true) {
      plPlayerController?.onLockControl(false);
      return;
    }
    if (isFullScreen) {
      plPlayerController!.triggerFullScreen(status: false);
    }
    if (MediaQuery.of(context).orientation == Orientation.landscape &&
        !horizontalScreen) {
      verticalScreenForTwoSeconds();
    }
  }

  void onShowMemberPage(mid) {
    videoDetailController.childKey.currentState?.showBottomSheet(
      (context) {
        return HorizontalMemberPage(
          mid: mid,
          videoDetailController: videoDetailController,
          videoIntroController: videoIntroController,
        );
      },
      enableDrag: true,
    );
  }
}
