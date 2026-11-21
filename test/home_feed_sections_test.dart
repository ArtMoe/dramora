import 'package:flutter_test/flutter_test.dart';
import 'package:guomu/hg/models/hg_models.dart';
import 'package:guomu/hg/pages/home_page.dart';

HgVideoCard card(int id, String title) =>
    HgVideoCard(id: id, title: title, cover: 'https://example.com/$id.jpg');

HgRankItem rank(int id, String title) => HgRankItem(
  rank: 1,
  videoId: id,
  title: title,
  cover: 'https://example.com/$id.jpg',
  tags: const [],
  score: 9,
  categoryName: '',
  episodeCount: 12,
  isFinished: false,
  metricLabel: '',
  metricValue: 0,
);

void main() {
  test('home sections remove duplicates across featured latest and hot', () {
    final sections = buildHomeFeedSections(
      featured: [card(1, '推荐一'), card(2, '推荐二'), card(3, '推荐三')],
      latest: [card(2, '上新二'), card(4, '上新四')],
      hot: [rank(3, '热播三'), rank(5, '热播五')],
    );

    expect(sections.featured.map((item) => item.id), [1, 2, 3]);
    expect(sections.latest.map((item) => item.id), [4]);
    expect(sections.hot.map((item) => item.videoId), [5]);
  });

  test('feedFor returns the section containing the video', () {
    final sections = buildHomeFeedSections(
      featured: [card(1, '推荐一'), card(2, '推荐二')],
      latest: [card(3, '上新三')],
      hot: [rank(4, '热播四')],
    );

    expect(sections.feedFor(2).map((item) => item.id), [1, 2]);
    expect(sections.feedFor(3).map((item) => item.id), [3]);
    expect(sections.feedFor(4).map((item) => item.id), [4]);
    expect(sections.feedFor(999), isEmpty);
  });
  test('deduplicates before limiting while preserving ranking metadata', () {
    final sections = buildHomeFeedSections(
      featured: [card(1, '推荐一'), card(1, '重复'), card(0, '无效')],
      latest: [
        card(1, '重复'),
        for (var id = 2; id <= 9; id++) card(id, '上新$id'),
      ],
      hot: [
        rank(1, '重复'),
        rank(2, '重复'),
        rank(8, '热播八'),
        rank(9, '热播九'),
        rank(10, '热播十'),
      ],
    );
    expect(sections.featured.map((item) => item.id), [1]);
    expect(sections.latest.map((item) => item.id), [2, 3, 4, 5, 6, 7]);
    expect(sections.hot.map((item) => item.videoId), [8, 9, 10]);
    expect(sections.hot.first.title, '热播八');
    expect(sections.hot.first.rank, 1);
    expect(sections.feedFor(8).map((item) => item.id), [8, 9, 10]);
    expect(() => sections.hot.clear(), throwsUnsupportedError);
  });
}
