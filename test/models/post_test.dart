import 'package:flutter_test/flutter_test.dart';
import 'package:news_feed_flutter/models/models.dart';
import 'package:shared_media/shared_media.dart';

Map<String, dynamic> postJson({List<Map<String, dynamic>>? media}) => {
      'id': 1,
      'author_id': 2,
      'body': '',
      'created_at': 3,
      'author_username': 'user_2',
      'media': ?media,
    };

Map<String, dynamic> mediaJson(int id, String kind) => {
      'id': id,
      'ownerId': 2,
      'kind': kind,
      'contentType': kind == 'image' ? 'image/jpeg' : 'video/mp4',
      'sizeBytes': 100,
      'width': 4,
      'height': 3,
      'durationMs': kind == 'video' ? 5000 : null,
      'url': 'https://bucket.test/$id',
    };

void main() {
  test('parses a post\'s media in order', () {
    final post = Post.fromJson(postJson(media: [mediaJson(8, 'video'), mediaJson(5, 'image')]));

    expect(post.media.map((m) => m.id), [8, 5]);
    expect(post.media.first.kind, MediaKind.video);
    expect(post.media.last.url, Uri.parse('https://bucket.test/5'));
  });

  test('a post from an older server without media has none', () {
    expect(Post.fromJson(postJson()).media, isEmpty);
  });
}
