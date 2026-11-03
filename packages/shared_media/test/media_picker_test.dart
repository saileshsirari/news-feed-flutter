import 'package:flutter_test/flutter_test.dart';
import 'package:shared_media/shared_media.dart';

void main() {
  test('uses the picker\'s MIME type when it has one', () {
    expect(MediaPicker.contentTypeFor('IMG_1.HEIC', 'image/png'), 'image/png');
    expect(MediaPicker.contentTypeFor('a.jpg', 'image/jpg'), 'image/jpeg'); // non-standard, seen on some Androids
  });

  test('falls back to the file extension', () {
    expect(MediaPicker.contentTypeFor('IMG_1.JPG', null), 'image/jpeg');
    expect(MediaPicker.contentTypeFor('photo.jpeg', ''), 'image/jpeg');
    expect(MediaPicker.contentTypeFor('scan.png', null), 'image/png');
    expect(MediaPicker.contentTypeFor('pic.webp', null), 'image/webp');
  });

  test('passes anything else through, for MediaLimits to reject clearly', () {
    expect(MediaPicker.contentTypeFor('IMG_1.HEIC', null), 'application/octet-stream');
  });
}
