import 'package:dio/dio.dart';
import 'package:kazumi/request/request.dart';
import 'package:kazumi/request/api.dart';
import 'package:kazumi/utils/utils.dart';
import 'package:logger/logger.dart';
import 'package:kazumi/utils/logger.dart';
import 'package:kazumi/utils/mortis.dart';
import 'package:kazumi/modules/danmaku/danmaku_module.dart';
import 'package:kazumi/modules/danmaku/danmaku_search_response.dart';
import 'package:kazumi/modules/danmaku/danmaku_episode_response.dart';
import 'package:kazumi/utils/string_match.dart';

class DanmakuRequest {

  // 从标题列表中获取番剧ID
  static Future<int> getBangumiIDByTitles(List<String> titleList) async {
    for (var title in titleList) {
      int bangumiID = await getBangumiID(title);
      if (bangumiID != 0) {
        return bangumiID;
      }
    }
    return 0;
  }

  //获取弹弹Play集合，需要进一步处理
  static Future<int> getBangumiID(String title) async {
    DanmakuSearchResponse danmakuSearchResponse =
        await getDanmakuSearchResponse(title);

    int bestAnimeId = 0;
    double maxSimilarity = 0;

    for (var anime in danmakuSearchResponse.animes) {
      int animeId = anime.animeId;
      if (animeId >= 100000 || animeId < 2) {
        continue;
      }

      String animeTitle = anime.animeTitle;
      double similarity = calculateSimilarity(animeTitle, title);
      if (similarity == 1) {
        KazumiLogger().log(Level.debug, '完全匹配番剧弹幕 $title');
        return animeId;
      }

      if (similarity > maxSimilarity) {
        maxSimilarity = similarity;
        bestAnimeId = animeId;
        KazumiLogger().log(Level.debug, '匹配番剧弹幕 $title --- $animeTitle 相似度: $similarity');
      }
    }

    return bestAnimeId;
  }

  //从BangumiID获取分集ID
  static Future<DanmakuEpisodeResponse> getDanDanEpisodesByBangumiID(
      int bangumiID) async {
    var path = Api.dandanAPIInfo + bangumiID.toString();
    var endPoint = Api.dandanAPIDomain + path;
    var timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    var httpHeaders = {
      'user-agent': Utils.getRandomUA(),
      'referer': '',
      'X-Auth': 1,
      'X-AppId': mortis['id'],
      'X-Timestamp': timestamp.toString(),
      'X-Signature': Utils.generateDandanSignature(path, timestamp),
    };
    final res = await Request().get(endPoint,
        options: Options(headers: httpHeaders),
        extra: {'customError': '弹幕检索错误: 获取弹幕分集ID失败'});
    Map<String, dynamic> jsonData = res.data;
    DanmakuEpisodeResponse danmakuEpisodeResponse =
        DanmakuEpisodeResponse.fromJson(jsonData);
    return danmakuEpisodeResponse;
  }

  static Future<DanmakuSearchResponse> getDanmakuSearchResponse(
      String title) async {
    var path = Api.dandanAPISearch;
    var endPoint = Api.dandanAPIDomain + path;
    var timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    var httpHeaders = {
      'user-agent': Utils.getRandomUA(),
      'referer': '',
      'X-Auth': 1,
      'X-AppId': mortis['id'],
      'X-Timestamp': timestamp.toString(),
      'X-Signature': Utils.generateDandanSignature(path, timestamp),
    };
    Map<String, String> keywordMap = {
      'keyword': title,
    };

    final res = await Request().get(endPoint,
        data: keywordMap,
        options: Options(headers: httpHeaders),
        extra: {'customError': '弹幕检索错误: 获取弹幕番剧ID失败'});
    Map<String, dynamic> jsonData = res.data;
    DanmakuSearchResponse danmakuSearchResponse =
        DanmakuSearchResponse.fromJson(jsonData);
    return danmakuSearchResponse;
  }

  static Future<List<Danmaku>> getDanDanmaku(int bangumiID, int episode) async {
    List<Danmaku> danmakus = [];
    if (bangumiID == 0) {
      return danmakus;
    }
    // 这里猜测了弹弹Play的分集命名规则，例如上面的番剧ID为1758，第一集弹幕库ID大概率为17580001，但是此命名规则并没有体现在官方API文档里，保险的做法是请求 Api.dandanInfo
    var path = Api.dandanAPIComment +
        bangumiID.toString() +
        episode.toString().padLeft(4, '0');
    var endPoint = Api.dandanAPIDomain + path;
    var timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    var httpHeaders = {
      'user-agent': Utils.getRandomUA(),
      'referer': '',
      'X-Auth': 1,
      'X-AppId': mortis['id'],
      'X-Timestamp': timestamp.toString(),
      'X-Signature': Utils.generateDandanSignature(path, timestamp),
    };
    Map<String, String> withRelated = {
      'withRelated': 'true',
    };
    KazumiLogger().log(Level.info, "弹幕请求最终URL $endPoint");
    final res = await Request().get(endPoint,
        data: withRelated,
        options: Options(headers: httpHeaders),
        extra: {'customError': '弹幕检索错误: 获取弹幕失败'});

    Map<String, dynamic> jsonData = res.data;
    List<dynamic> comments = jsonData['comments'];

    for (var comment in comments) {
      Danmaku danmaku = Danmaku.fromJson(comment);
      danmakus.add(danmaku);
    }
    return danmakus;
  }

  static Future<List<Danmaku>> getDanDanmakuByEpisodeID(int episodeID) async {
    var path = Api.dandanAPIComment + episodeID.toString();
    var endPoint = Api.dandanAPIDomain + path;
    var timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    List<Danmaku> danmakus = [];
    var httpHeaders = {
      'user-agent': Utils.getRandomUA(),
      'referer': '',
      'X-Auth': 1,
      'X-AppId': mortis['id'],
      'X-Timestamp': timestamp.toString(),
      'X-Signature': Utils.generateDandanSignature(path, timestamp),
    };
    Map<String, String> withRelated = {
      'withRelated': 'true',
    };
    final res = await Request().get(endPoint,
        data: withRelated,
        options: Options(headers: httpHeaders),
        extra: {'customError': '弹幕检索错误: 获取弹幕失败'});
    Map<String, dynamic> jsonData = res.data;
    List<dynamic> comments = jsonData['comments'];

    for (var comment in comments) {
      Danmaku danmaku = Danmaku.fromJson(comment);
      danmakus.add(danmaku);
    }
    return danmakus;
  }
}
