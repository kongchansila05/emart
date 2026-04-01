import 'package:EMART24/features/home/data/remote/remote_banner.dart';

abstract class BannerRepository {
  Future<List<RemoteBanner>> fetchActiveBanners({String position = 'top'});
}
