import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:EMART24/core/config/app_environment.dart';
import 'package:EMART24/core/network/api_client.dart';
import 'package:EMART24/core/network/api_endpoints.dart';
import 'package:EMART24/core/network/api_exception.dart';

// ── Upload limits (used for UI validation before picking images) ──────────────

class PostUploadLimits {
  const PostUploadLimits({this.perImageBytes, this.totalBytes});
  final int? perImageBytes;
  final int? totalBytes;
  bool get hasAny => perImageBytes != null || totalBytes != null;
}

// ── Result returned to the caller ─────────────────────────────────────────────

class CreatePostResult {
  const CreatePostResult({required this.post, required this.uploadedUrls});

  /// The created post object from the server.
  final Map<String, dynamic> post;

  /// R2 public URLs that were uploaded before the post was saved.
  final List<String> uploadedUrls;
}

// ── Service ───────────────────────────────────────────────────────────────────

class CreatePostApiService {
  CreatePostApiService({ApiClient? client})
    : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  // ───────────────────────────────────────────────────────────────────────────
  // STEP 1 — Upload a single image file to R2, return its public URL.
  //
  // Endpoint : POST /api/admin/upload  (ApiEndpoints.uploadImage)
  // Request  : multipart/form-data  { file: <binary>, folder: "posts" }
  // Response : { "url": "https://cdn.r2.example.com/posts/..." }
  //
  // Vue equivalent:
  //   const { data } = await uploadApi.image(file, 'posts')
  //   imageUrls.push(data.url)
  // ───────────────────────────────────────────────────────────────────────────
  Future<String> uploadImageToR2(String filePath) async {
    final String trimmed = filePath.trim();
    _log('📤 Uploading to R2: ${_fileName(trimmed)}');

    final FormData formData = FormData.fromMap(<String, dynamic>{
      'file': await MultipartFile.fromFile(
        trimmed,
        filename: _fileName(trimmed),
      ),
      'folder': 'posts',
    });

    try {
      final Response<dynamic> response = await _client.dio.post<dynamic>(
        ApiEndpoints.uploadImage, // POST /api/admin/upload
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
      );

      _logResponse(response.statusCode, response.data);

      // Server returns { "url": "https://..." }
      final dynamic body = response.data;
      if (body is Map<String, dynamic> && body['url'] is String) {
        return body['url'] as String;
      }
      throw ApiException(
        type: ApiErrorType.unknown,
        statusCode: response.statusCode ?? 0,
        message: 'Upload response missing "url" field. Got: $body',
      );
    } on DioException catch (e) {
      _logError(e);
      throw ApiException.fromDioException(e);
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // STEP 2 — Upload all images to R2 first, then POST the post as JSON.
  //
  // Endpoint : POST /api/posts  (ApiEndpoints.createPost)
  // Request  : application/json
  // Body     : { title, description, price, category_id, images: ["https://..."] }
  //
  // Vue equivalent (saveCreate):
  //   await postsApi.adminCreate({ ...form, images: imageUrls })
  // ───────────────────────────────────────────────────────────────────────────
  Future<CreatePostResult> createPost({
    required String title,
    required String description,
    required double price,
    required int categoryId,
    String status = 'active',
    String? location,
    double? latitude,
    double? longitude,
    String? condition,
    List<String> imagePaths = const <String>[],
  }) async {
    // ── Mock path ──────────────────────────────────────────────────────────
    if (AppEnvironment.useMockApi) {
      return CreatePostResult(
        post: <String, dynamic>{
          'id': 'mock-created-post',
          'title': title.trim(),
          'description': description.trim(),
          'price': price,
          'category_id': categoryId,
          'status': status,
          'location': location,
          'latitude': latitude,
          'longitude': longitude,
          'condition': condition,
          'images': jsonEncode(imagePaths), // ✅ fixed
        },
        uploadedUrls: imagePaths,
      );
    }

    // ── Step 1: upload each image to R2 ────────────────────────────────────
    final List<String> imageUrls = <String>[];
    for (final String path in imagePaths) {
      if (path.trim().isEmpty) continue;
      final String url = await uploadImageToR2(path);
      imageUrls.add(url);
      _log('✅ R2 URL: $url');
    }

    // ── Step 2: build JSON body ─────────────────────────────────────────────
    final Map<String, dynamic> payload = <String, dynamic>{
      'title':       title.trim(),
      'description': description.trim(),
      'price':       price,
      'status':      status.trim().isEmpty ? 'active' : status.trim(),
      'category_id': categoryId,
      'images':      jsonEncode(imageUrls), // ✅ fixed — stores as "[\"url1\",\"url2\"]"
      if (location != null && location.trim().isNotEmpty)
        'location': location.trim(),
      if (latitude  != null) 'latitude':  latitude,
      if (longitude != null) 'longitude': longitude,
      if (condition != null && condition.trim().isNotEmpty)
        'condition': condition.trim(),
    };

    _logRequest('POST', ApiEndpoints.createPost, payload);

    // ── Step 3: POST as application/json ────────────────────────────────────
    try {
      final dynamic response = await _client.post<dynamic>(
        ApiEndpoints.createPost,
        data: payload,
        options: Options(
          headers: <String, String>{'Content-Type': 'application/json'},
        ),
      );

      _logResponse(200, response);
      return CreatePostResult(
        post: _extractMap(response),
        uploadedUrls: imageUrls,
      );
    } on DioException catch (e) {
      _logError(e);
      throw ApiException.fromDioException(e);
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Upload limits discovery
  // ───────────────────────────────────────────────────────────────────────────

  Future<PostUploadLimits?> fetchUploadLimits() async {
    if (AppEnvironment.useMockApi) {
      return const PostUploadLimits(
        perImageBytes: 5 * 1024 * 1024,
        totalBytes: 20 * 1024 * 1024,
      );
    }

    final List<({String method, String path, Map<String, dynamic>? query})>
    attempts = <({String method, String path, Map<String, dynamic>? query})>[
      (method: 'OPTIONS', path: ApiEndpoints.createPost, query: null),
      (
        method: 'GET',
        path: ApiEndpoints.publicPosts,
        query: <String, dynamic>{'page': 1, 'limit': 1},
      ),
    ];

    for (final attempt in attempts) {
      try {
        final Response<dynamic> response = await _client.dio.request<dynamic>(
          attempt.path,
          queryParameters: attempt.query,
          options: Options(method: attempt.method),
        );
        final PostUploadLimits? parsed = _extractUploadLimits(
          responseData: response.data,
          responseHeaders: response.headers.map,
        );
        if (parsed != null && parsed.hasAny) return parsed;
      } catch (_) {/* ignore */}
    }
    return null;
  }

  PostUploadLimits? extractUploadLimitsFromDioError(DioException error) {
    final Response<dynamic>? response = error.response;
    if (response == null) return null;
    return _extractUploadLimits(
      responseData: response.data,
      responseHeaders: response.headers.map,
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Logging helpers
  // ───────────────────────────────────────────────────────────────────────────

  void _log(String msg) => print('[CreatePostApiService] $msg');

  void _logRequest(String method, String path, Map<String, dynamic> body) {
    print('');
    print('┌─────────────────────────────────────────────');
    print('│ [CreatePostApiService] ➡ REQUEST');
    print('│ $method $path');
    print('│ Content-Type : application/json');
    print('│ Body:');
    _prettyPrintMap(body);
    print('└─────────────────────────────────────────────');
  }

  void _logResponse(int? statusCode, dynamic data) {
    print('');
    print('┌─────────────────────────────────────────────');
    print('│ [CreatePostApiService] ✅ RESPONSE $statusCode');
    print('│ Body:');
    try {
      final String pretty = const JsonEncoder.withIndent('  ').convert(data);
      for (final String line in pretty.split('\n')) {
        print('│   $line');
      }
    } catch (_) {
      print('│   $data');
    }
    print('└─────────────────────────────────────────────');
  }

  void _logError(DioException error) {
    print('');
    print('┌─────────────────────────────────────────────');
    print('│ [CreatePostApiService] ❌ ERROR');
    print('│ Status  : ${error.response?.statusCode}');
    print('│ Type    : ${error.type}');
    final dynamic rawData = error.response?.data;
    if (rawData != null) {
      print('│ Response body (raw)   : $rawData');
      print('│ Response body (pretty):');
      try {
        final dynamic decoded =
            rawData is String ? jsonDecode(rawData) : rawData;
        final String pretty =
            const JsonEncoder.withIndent('  ').convert(decoded);
        for (final String line in pretty.split('\n')) {
          print('│   $line');
        }
      } catch (_) {
        print('│   (not valid JSON)');
      }
    }
    print('│ Request URL    : ${error.requestOptions.uri}');
    print('│ Request method : ${error.requestOptions.method}');
    print('└─────────────────────────────────────────────');
  }

  void _prettyPrintMap(Map<String, dynamic> map) {
    try {
      final String pretty = const JsonEncoder.withIndent('  ').convert(map);
      for (final String line in pretty.split('\n')) {
        print('│   $line');
      }
    } catch (_) {
      map.forEach((String k, dynamic v) => print('│   $k: $v'));
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Private helpers
  // ───────────────────────────────────────────────────────────────────────────

  Map<String, dynamic> _extractMap(dynamic response) {
    if (response is Map<String, dynamic>) {
      if (response['data'] is Map<String, dynamic>) {
        return response['data'] as Map<String, dynamic>;
      }
      return response;
    }
    return <String, dynamic>{};
  }

  String _fileName(String path) {
    final int i = path.lastIndexOf('/');
    if (i < 0 || i == path.length - 1) return 'image.jpg';
    return path.substring(i + 1);
  }

  // ── Upload limit parsing ──────────────────────────────────────────────────

  PostUploadLimits? _extractUploadLimits({
    required dynamic responseData,
    required Map<String, List<String>> responseHeaders,
  }) {
    int? inferredPerImage =
        _findLimitBytesInPayload(responseData, keys: _perImageLimitKeys) ??
        _findLimitBytesInHeaders(responseHeaders, keys: _perImageLimitKeys);
    int? inferredTotal =
        _findLimitBytesInPayload(responseData, keys: _totalLimitKeys) ??
        _findLimitBytesInHeaders(responseHeaders, keys: _totalLimitKeys);

    if (inferredPerImage == null || inferredTotal == null) {
      final String text = _flattenText(responseData).toLowerCase();
      final int? fallback = _parseBytes(text);
      if (fallback != null) {
        if (text.contains('image') || text.contains('file') || text.contains('each')) {
          inferredPerImage ??= fallback;
        } else if (text.contains('request') || text.contains('payload') ||
                   text.contains('total')   || text.contains('body')    ||
                   text.contains('upload')) {
          inferredTotal ??= fallback;
        }
      }
    }

    if (inferredPerImage == null && inferredTotal == null) return null;
    return PostUploadLimits(
      perImageBytes: inferredPerImage,
      totalBytes: inferredTotal,
    );
  }

  int? _findLimitBytesInHeaders(
    Map<String, List<String>> headers, {
    required Set<String> keys,
  }) {
    for (final entry in headers.entries) {
      final String key = _normalizeKey(entry.key);
      if (!keys.contains(key)) continue;
      for (final String v in entry.value) {
        final int? p = _parseBytes(v, keyHint: key);
        if (p != null && p > 0) return p;
      }
    }
    return null;
  }

  int? _findLimitBytesInPayload(
    dynamic payload, {
    required Set<String> keys,
    int depth = 0,
  }) {
    if (payload == null || depth > 5) return null;
    final dynamic n = _tryDecodeJsonString(payload);
    if (n is Map) {
      for (final entry in n.entries) {
        final String key = _normalizeKey(entry.key.toString());
        if (keys.contains(key)) {
          final int? p = _parseBytes(entry.value, keyHint: key);
          if (p != null && p > 0) return p;
        }
        final int? nested =
            _findLimitBytesInPayload(entry.value, keys: keys, depth: depth + 1);
        if (nested != null && nested > 0) return nested;
      }
      return null;
    }
    if (n is List) {
      for (final item in n) {
        final int? nested =
            _findLimitBytesInPayload(item, keys: keys, depth: depth + 1);
        if (nested != null && nested > 0) return nested;
      }
    }
    return null;
  }

  dynamic _tryDecodeJsonString(dynamic value) {
    if (value is! String) return value;
    final String t = value.trim();
    if (t.isEmpty) return value;
    if (!((t.startsWith('{') && t.endsWith('}')) ||
          (t.startsWith('[') && t.endsWith(']')))) return value;
    try {
      return jsonDecode(t);
    } catch (_) {
      return value;
    }
  }

  String _normalizeKey(String value) {
    final StringBuffer b = StringBuffer();
    for (final int code in value.toLowerCase().codeUnits) {
      if ((code >= 48 && code <= 57) || (code >= 97 && code <= 122)) {
        b.writeCharCode(code);
      }
    }
    return b.toString();
  }

  int? _parseBytes(dynamic value, {String? keyHint}) {
    if (value == null) return null;
    if (value is num) return _scaleByKeyHint(value.toDouble(), keyHint: keyHint);
    final String text = value.toString().trim();
    if (text.isEmpty) return null;
    final ({double amount, String unit})? sized = _extractSizedValue(text);
    if (sized != null) {
      if (sized.amount <= 0) return null;
      if (sized.unit.startsWith('g')) return (sized.amount * 1024 * 1024 * 1024).round();
      if (sized.unit.startsWith('m')) return (sized.amount * 1024 * 1024).round();
      if (sized.unit.startsWith('k')) return (sized.amount * 1024).round();
      return sized.amount.round();
    }
    final double? n = double.tryParse(text);
    if (n == null || n <= 0) return null;
    return _scaleByKeyHint(n, keyHint: keyHint);
  }

  ({double amount, String unit})? _extractSizedValue(String text) {
    final List<String> tokens = _tokenize(text);
    for (int i = 0; i < tokens.length; i++) {
      final String token = tokens[i];
      if (token.isEmpty) continue;
      final ({String numberPart, String unitPart}) s = _splitToken(token);
      if (s.numberPart.isEmpty) continue;
      final double? amount = double.tryParse(s.numberPart);
      if (amount == null || amount <= 0) continue;
      String unit = s.unitPart;
      if (unit.isEmpty && i + 1 < tokens.length && _isSupportedUnit(tokens[i + 1])) {
        unit = tokens[i + 1];
      }
      if (_isSupportedUnit(unit)) return (amount: amount, unit: unit);
    }
    return null;
  }

  List<String> _tokenize(String raw) {
    final List<String> tokens = <String>[];
    final StringBuffer cur = StringBuffer();
    void flush() {
      if (cur.isNotEmpty) {
        tokens.add(cur.toString());
        cur.clear();
      }
    }
    for (final String char in raw.toLowerCase().split('')) {
      final int code = char.codeUnitAt(0);
      if ((code >= 97 && code <= 122) || (code >= 48 && code <= 57) || code == 46) {
        cur.write(char);
      } else {
        flush();
      }
    }
    flush();
    return tokens;
  }

  ({String numberPart, String unitPart}) _splitToken(String token) {
    int i = 0;
    while (i < token.length) {
      final int code = token.codeUnitAt(i);
      if ((code < 48 || code > 57) && code != 46) break;
      i++;
    }
    return (numberPart: token.substring(0, i), unitPart: token.substring(i));
  }

  bool _isSupportedUnit(String u) =>
      u == 'gb' || u == 'gib' || u == 'mb' || u == 'mib' ||
      u == 'kb' || u == 'kib' || u == 'byte' || u == 'bytes' || u == 'b';

  int? _scaleByKeyHint(double value, {String? keyHint}) {
    if (value <= 0) return null;
    final String h = (keyHint ?? '').toLowerCase();
    if (h.contains('gb') || h.contains('gib')) return (value * 1024 * 1024 * 1024).round();
    if (h.contains('mb') || h.contains('mib')) return (value * 1024 * 1024).round();
    if (h.contains('kb') || h.contains('kib')) return (value * 1024).round();
    return value.round();
  }

  String _flattenText(dynamic data, {int depth = 0}) {
    if (data == null || depth > 4) return '';
    if (data is String) return data;
    if (data is num || data is bool) return data.toString();
    if (data is Map) {
      return data.values
          .map((dynamic i) => _flattenText(i, depth: depth + 1))
          .where((String v) => v.trim().isNotEmpty)
          .join(' ');
    }
    if (data is List) {
      return data
          .map((dynamic i) => _flattenText(i, depth: depth + 1))
          .where((String v) => v.trim().isNotEmpty)
          .join(' ');
    }
    return data.toString();
  }

  static const Set<String> _perImageLimitKeys = <String>{
    'maximagesize', 'maximagesizebytes', 'maximagesizemb',
    'maxfilesize', 'maxfilesizebytes', 'maxfilesizemb',
    'imagesizelimit', 'imagesizelimitbytes', 'imagesizelimitmb',
    'filesizelimit', 'filesizelimitbytes', 'filesizelimitmb',
    'maximageuploadsize', 'maximageuploadsizebytes', 'maximageuploadsizemb',
    'imageuploadlimit', 'imageuploadlimitbytes', 'imagemaxsize',
  };

  static const Set<String> _totalLimitKeys = <String>{
    'maxtotaluploadsize', 'maxtotaluploadsizebytes', 'maxtotaluploadsizemb',
    'maxuploadsize', 'maxuploadsizebytes', 'maxuploadsizemb',
    'maxrequestsize', 'maxrequestsizebytes', 'maxrequestsizemb',
    'maxbodysize', 'maxbodysizebytes', 'maxbodysizemb',
    'requestsizelimit', 'requestsizelimitbytes',
    'uploadsizelimit', 'uploadsizelimitbytes',
    'contentlengthlimit', 'payloadsizelimit',
  };
}