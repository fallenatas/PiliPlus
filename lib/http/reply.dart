import 'dart:io';

import 'package:PiliPalaX/http/loading_state.dart';
import 'package:PiliPalaX/utils/storage.dart';
import 'package:dio/dio.dart';

import '../models/video/reply/data.dart';
import '../models/video/reply/emote.dart';
import 'api.dart';
import 'constants.dart';
import 'init.dart';

class ReplyHttp {
  static Future<LoadingState> replyList({
    required int oid,
    required int type,
    int sort = 1,
    required int page,
  }) async {
    Options? options = GStorage.userInfo.get('userInfoCache') == null
        ? Options(
            headers: {HttpHeaders.cookieHeader: "buvid3= ; b_nut= ; sid= "})
        : null;
    var res = await Request().get(
      '${HttpString.apiBaseUrl}${Api.replyList}',
      data: {
        'oid': oid,
        'type': type,
        'sort': sort,
        'pn': page,
        'ps': 20,
      },
      options: options,
    );
    if (res.data['code'] == 0) {
      return LoadingState.success(ReplyData.fromJson(res.data['data']));
    } else {
      return LoadingState.error(res.data['message']);
    }
  }

  static Future<LoadingState> replyReplyList({
    required int oid,
    required String root,
    required int pageNum,
    required int type,
    int sort = 1,
  }) async {
    Options? options = GStorage.userInfo.get('userInfoCache') == null
        ? Options(
            headers: {HttpHeaders.cookieHeader: "buvid3= ; b_nut= ; sid= "})
        : null;
    var res = await Request().get(
      '${HttpString.apiBaseUrl}${Api.replyReplyList}',
      data: {
        'oid': oid,
        'root': root,
        'pn': pageNum,
        'type': type,
        'sort': 1,
        'csrf': await Request.getCsrf(),
      },
      options: options,
    );
    if (res.data['code'] == 0) {
      return LoadingState.success(ReplyReplyData.fromJson(res.data['data']));
    } else {
      return LoadingState.error(res.data['message']);
    }
  }

  // 评论点赞
  static Future likeReply({
    required int type,
    required int oid,
    required int rpid,
    required int action,
  }) async {
    var res = await Request().post(
      Api.likeReply,
      queryParameters: {
        'type': type,
        'oid': oid,
        'rpid': rpid,
        'action': action,
        'csrf': await Request.getCsrf(),
      },
    );
    if (res.data['code'] == 0) {
      return {'status': true, 'data': res.data['data']};
    } else {
      return {
        'status': false,
        'date': [],
        'msg': res.data['message'],
      };
    }
  }

  static Future<LoadingState> getEmoteList({String? business}) async {
    var res = await Request().get(Api.myEmote, data: {
      'business': business ?? 'reply',
      'web_location': '333.1245',
    });
    if (res.data['code'] == 0) {
      return LoadingState.success(
          EmoteModelData.fromJson(res.data['data']).packages);
    } else {
      return LoadingState.error(res.data['message']);
    }
  }
}
