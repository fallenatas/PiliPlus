import 'package:PiliPalaX/common/constants.dart';
import 'package:PiliPalaX/common/widgets/loading_widget.dart';
import 'package:PiliPalaX/http/loading_state.dart';
import 'package:PiliPalaX/pages/follow/widgets/follow_item.dart';
import 'package:PiliPalaX/pages/history/widgets/item.dart';
import 'package:PiliPalaX/utils/grid.dart';
import 'package:easy_debounce/easy_throttle.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:PiliPalaX/pages/fav_detail/widget/fav_video_card.dart';

import 'controller.dart';

enum SearchType { fav, follow, history }

class FavSearchPage extends StatefulWidget {
  const FavSearchPage({super.key});

  @override
  State<FavSearchPage> createState() => _FavSearchPageState();
}

class _FavSearchPageState extends State<FavSearchPage> {
  final FavSearchController _favSearchCtr = Get.put(FavSearchController());

  @override
  void initState() {
    super.initState();
    _favSearchCtr.scrollController.addListener(
      () {
        if (_favSearchCtr.scrollController.position.pixels >=
            _favSearchCtr.scrollController.position.maxScrollExtent - 300) {
          EasyThrottle.throttle('fav', const Duration(seconds: 1), () {
            _favSearchCtr.onLoadMore();
          });
        }
      },
    );
  }

  @override
  void dispose() {
    _favSearchCtr.scrollController.removeListener(() {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        actions: [
          IconButton(
              tooltip: '搜索',
              onPressed: _favSearchCtr.onRefresh,
              icon: const Icon(Icons.search_outlined, size: 22)),
          const SizedBox(width: 10)
        ],
        title: Obx(
          () => TextField(
            autofocus: true,
            focusNode: _favSearchCtr.searchFocusNode,
            controller: _favSearchCtr.controller.value,
            textInputAction: TextInputAction.search,
            onChanged: (value) => _favSearchCtr.onChange(value),
            textAlignVertical: TextAlignVertical.center,
            decoration: InputDecoration(
              hintText: _favSearchCtr.hintText,
              border: InputBorder.none,
              suffixIcon: IconButton(
                tooltip: '清空',
                icon: const Icon(Icons.clear, size: 22),
                onPressed: () => _favSearchCtr.onClear(),
              ),
            ),
            onSubmitted: (String value) => _favSearchCtr.onRefresh(),
          ),
        ),
      ),
      body: Obx(() => _buildBody(_favSearchCtr.loadingState.value)),
    );
  }

  Widget _buildBody(LoadingState loadingState) {
    return switch (loadingState) {
      Loading() => errorWidget(),
      Success() => (loadingState.response as List?)?.isNotEmpty == true
          ? _favSearchCtr.searchType == SearchType.fav
              ? ListView.separated(
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
                  controller: _favSearchCtr.scrollController,
                  itemCount: loadingState.response.length + 1,
                  itemBuilder: (context, index) {
                    if (index == loadingState.response.length) {
                      return Container(
                        height: MediaQuery.of(context).padding.bottom + 60,
                        padding: EdgeInsets.only(
                          bottom: MediaQuery.of(context).padding.bottom,
                        ),
                      );
                    } else {
                      return FavVideoCardH(
                        videoItem: loadingState.response[index],
                        searchType: _favSearchCtr.type,
                        callFn: () => _favSearchCtr.type != 1
                            ? _favSearchCtr
                                .onCancelFav(loadingState.response[index].id!)
                            : {},
                      );
                    }
                  },
                )
              : _favSearchCtr.searchType == SearchType.follow
                  ? ListView.builder(
                      controller: _favSearchCtr.scrollController,
                      itemCount: loadingState.response.length,
                      itemBuilder: ((context, index) {
                        return FollowItem(
                          item: loadingState.response[index],
                        );
                      }),
                    )
                  : CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      controller: _favSearchCtr.scrollController,
                      slivers: [
                        SliverGrid(
                          gridDelegate: SliverGridDelegateWithExtentAndRatio(
                              mainAxisSpacing: StyleString.cardSpace,
                              crossAxisSpacing: StyleString.safeSpace,
                              maxCrossAxisExtent: Grid.maxRowWidth * 2,
                              childAspectRatio: StyleString.aspectRatio * 2.4,
                              mainAxisExtent: 0),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              return HistoryItem(
                                videoItem: loadingState.response[index],
                                ctr: _favSearchCtr,
                                onChoose: null,
                                onUpdateMultiple: () => null,
                              );
                            },
                            childCount: loadingState.response.length,
                          ),
                        ),
                      ],
                    )
          : errorWidget(
              callback: _favSearchCtr.onReload,
            ),
      Error() => errorWidget(
          errMsg: loadingState.errMsg,
          callback: _favSearchCtr.onReload,
        ),
      LoadingState() => throw UnimplementedError(),
    };
  }
}
