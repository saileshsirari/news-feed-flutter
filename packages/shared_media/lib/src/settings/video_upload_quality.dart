/// How phone videos are compressed before upload. The bitrates are what
/// these settings produced on a Samsung S22 (video plus its audio); they
/// drive the size and time estimates shown when choosing, which is the
/// point of the choice: smaller means a faster upload.
enum VideoUploadQuality {
  original('Original', 'No compression, best quality', 17.0),
  p1080('1080p', 'Full HD', 9.2),
  p720('720p', 'HD', 4.2),
  p540('540p', 'Looks good on phones', 2.5),
  p480('480p', 'Fastest, noticeably softer', 1.6);

  const VideoUploadQuality(this.label, this.description, this.approxMbitPerSecond);

  final String label;
  final String description;

  /// What a typical phone clip comes out at; the original's depends on the
  /// phone and its camera settings.
  final double approxMbitPerSecond;

  /// The default for anyone who hasn't chosen.
  static const recommended = p540;

  /// The upload speed the time estimates assume: ordinary mobile data.
  static const typicalUploadMbitPerSecond = 5.0;

  bool get compresses => this != original;

  /// Estimated size of a clip of [seconds], in MB.
  double approxMegabytes(int seconds) => approxMbitPerSecond * seconds / 8;

  /// Estimated upload time for a clip of [seconds] at [typicalUploadMbitPerSecond].
  int approxUploadSeconds(int seconds) => (approxMbitPerSecond * seconds / typicalUploadMbitPerSecond).round();

  static VideoUploadQuality? fromName(String? name) {
    for (final quality in values) {
      if (quality.name == name) return quality;
    }
    return null;
  }
}
