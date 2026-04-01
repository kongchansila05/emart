import 'package:EMART24/core/network/api_client.dart';
import 'package:EMART24/core/storage/token_storage.dart';

class NetworkBootstrap {
  NetworkBootstrap._();

  static Future<void> init({RefreshTokenHandler? refreshTokenHandler}) async {
    ApiClient.instance.configure(
      accessTokenProvider: TokenStorage.getAccessToken,
      refreshTokenHandler: refreshTokenHandler,
    );
  }
}
