import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:EMART24/core/network/api_exception.dart';
import 'package:EMART24/core/theme/app_color.dart';
import 'package:EMART24/core/utils/price_input_utils.dart';
import 'package:EMART24/features/sell/data/remote/create_post_api_service.dart';
import 'package:EMART24/features/sell/presentation/location_picker_card.dart';
import 'package:EMART24/features/sell/presentation/location_picker_screen.dart';
import 'package:EMART24/shared/widgets/forms/form_layout.dart';

class _SelectOption<T> {
  const _SelectOption({required this.value, required this.label});

  final T value;
  final String label;
}

List<DropdownMenuItem<T>> _buildSelectMenuItems<T>(
  List<_SelectOption<T>> items,
) {
  return items
      .map(
        (item) =>
            DropdownMenuItem<T>(value: item.value, child: Text(item.label)),
      )
      .toList(growable: false);
}

class CreatePostForm extends StatefulWidget {
  final String? initialCategoryId;
  final String? initialSubCategoryId;

  const CreatePostForm({
    super.key,
    this.initialCategoryId,
    this.initialSubCategoryId,
  });

  @override
  State<CreatePostForm> createState() => _CreatePostFormState();
}

class _CreatePostFormState extends State<CreatePostForm> {
  final CreatePostApiService _createPostApiService = CreatePostApiService();
  final ImagePicker _imagePicker = ImagePicker();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();

  final List<XFile> _pickedImages = <XFile>[];
  int? _resolvedCategoryId;

  // ── Location state ─────────────────────────────────────────────────────────
  double? _pickedLatitude;
  double? _pickedLongitude;
  String? _pickedAddress;
  String? _pickedCity;
  bool _locationTouched = false;

  bool _isSaving = false;
  String? _imageErrorText;
  AutovalidateMode _autoValidateMode = AutovalidateMode.disabled;

  String _selectedStatus = 'active';
  String? _selectedCondition;

  static const Color _accentColor = Color(0xFF6F63FF);
  static const Color _fieldBorderColor = Color(0xFFD6DBEE);
  static const Color _fieldHintColor = Color(0xFF8E95B1);
  static const int _bytesPerMb = 1024 * 1024;
  static const int _defaultMaxImageSizeMb = 2;
  static const int _defaultMaxTotalImageUploadMb = 6;
  static const int _fallback413PerImageLimitMb = 1;
  static const int _fallback413TotalLimitMb = 3;

  static const List<_SelectOption<String>> _statusOptions =
      <_SelectOption<String>>[
        _SelectOption<String>(value: 'active', label: 'Active'),
        _SelectOption<String>(value: 'pending', label: 'Pending'),
        _SelectOption<String>(value: 'sold', label: 'Sold'),
      ];
  static const List<_SelectOption<String>> _conditionOptions =
      <_SelectOption<String>>[
        _SelectOption<String>(value: 'new', label: 'New'),
        _SelectOption<String>(value: 'like_new', label: 'Like New'),
        _SelectOption<String>(value: 'good', label: 'Good'),
        _SelectOption<String>(value: 'fair', label: 'Fair'),
        _SelectOption<String>(value: 'poor', label: 'Poor'),
      ];
  static final List<DropdownMenuItem<String>> _statusDropdownItems =
      _buildSelectMenuItems(_statusOptions);
  static final List<DropdownMenuItem<String>> _conditionDropdownItems =
      _buildSelectMenuItems(_conditionOptions);

  int _maxImageSizeBytes = _defaultMaxImageSizeMb * _bytesPerMb;
  int _maxTotalImageUploadBytes = _defaultMaxTotalImageUploadMb * _bytesPerMb;

  bool get _isBusy => _isSaving;
  bool get _hasLocation => _pickedLatitude != null && _pickedLongitude != null;
  String get _maxImageSizeMbLabel => _formatMbLabel(_maxImageSizeBytes);
  String get _maxTotalImageUploadMbLabel =>
      _formatMbLabel(_maxTotalImageUploadBytes);

  @override
  void initState() {
    super.initState();
    _resolvedCategoryId = int.tryParse((widget.initialCategoryId ?? '').trim());
    _loadUploadLimitsFromApi();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  // ── Location ───────────────────────────────────────────────────────────────

  void _onLocationPicked(LocationPickerResult result) {
    final List<String> parts =
        (result.address ?? '').split(',').map((s) => s.trim()).toList();
    setState(() {
      _pickedLatitude = result.latitude;
      _pickedLongitude = result.longitude;
      _pickedAddress = result.address;
      _pickedCity = parts.length >= 2
          ? '${parts[parts.length - 2]}, ${parts.last}'
          : result.address;
      _locationTouched = true;
    });
  }

  // ── Images ─────────────────────────────────────────────────────────────────

  Future<void> _pickImages() async {
    try {
      final List<XFile> images = await _imagePicker.pickMultiImage(
        imageQuality: 70,
        maxWidth: 1280,
        maxHeight: 1280,
      );
      if (!mounted || images.isEmpty) return;
      final List<XFile> valid =
          await _filterImagesBySize(images, notifyOnInvalid: true);
      if (!mounted || valid.isEmpty) return;
      final Map<String, XFile> deduped = <String, XFile>{
        for (final XFile f in _pickedImages) f.path: f,
      };
      for (final XFile f in valid) {
        deduped[f.path] = f;
      }
      setState(() {
        _pickedImages
          ..clear()
          ..addAll(deduped.values);
        _imageErrorText = null;
      });
    } catch (_) {
      _showSnack('Unable to pick images.');
    }
  }

  Future<List<XFile>> _filterImagesBySize(
    List<XFile> files, {
    bool notifyOnInvalid = false,
  }) async {
    final List<XFile> valid = <XFile>[];
    int invalid = 0;
    for (final XFile f in files) {
      try {
        if (await f.length() <= _maxImageSizeBytes) {
          valid.add(f);
          continue;
        }
      } catch (_) {}
      invalid++;
    }
    if (notifyOnInvalid && invalid > 0) {
      _showSnack(
          '$invalid image(s) skipped — max $_maxImageSizeMbLabel MB each.');
    }
    return valid;
  }

  Future<int> _totalImageBytes(Iterable<XFile> files) async {
    int total = 0;
    for (final XFile f in files) {
      try {
        total += await f.length();
      } catch (_) {}
    }
    return total;
  }

  // ── Submit ─────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (_isSaving) return;
    final int? categoryId = _resolvedCategoryId;
    if (categoryId == null) {
      _showSnack('Missing category. Please go back and choose one.');
      return;
    }
    final bool hasImages = _pickedImages.isNotEmpty;
    setState(() {
      _autoValidateMode = AutovalidateMode.onUserInteraction;
      _imageErrorText = hasImages ? null : 'Image is required';
      _locationTouched = true;
    });
    final bool formValid = _formKey.currentState?.validate() ?? false;
    if (!formValid || !hasImages) return;
    final double? price = PriceInputUtils.tryParseNumber(_priceController.text);
    if (price == null || price <= 0) {
      _showSnack('Please enter a valid price.');
      return;
    }
    if (!_hasLocation) {
      _showSnack('Please set a location on the map.');
      return;
    }
    final List<XFile> validImages = await _filterImagesBySize(_pickedImages);
    if (!mounted) return;
    if (validImages.length != _pickedImages.length) {
      setState(() {
        _pickedImages
          ..clear()
          ..addAll(validImages);
      });
      _showSnack('Some images removed — max $_maxImageSizeMbLabel MB each.');
    }
    if (validImages.isEmpty) {
      setState(() => _imageErrorText = 'Image is required');
      return;
    }
    final int totalBytes = await _totalImageBytes(validImages);
    if (!mounted) return;
    if (totalBytes > _maxTotalImageUploadBytes) {
      _showSnack('Total too large — keep under $_maxTotalImageUploadMbLabel MB.');
      return;
    }
    setState(() => _isSaving = true);
    try {
      await _createPostApiService.createPost(
        title: _titleController.text.trim(),
        description: _normalizeDescription(_descriptionController.text),
        price: price,
        categoryId: categoryId,
        status: _selectedStatus,
        location: _pickedAddress,
        latitude: _pickedLatitude,
        longitude: _pickedLongitude,
        condition: _selectedCondition,
        imagePaths: validImages.map((f) => f.path).toList(),
      );
      if (!mounted) return;
      _showSnack('Post created successfully.');
      _resetFormToDefaults();
    } on ApiException catch (error) {
      if (!mounted) return;
      String message = error.message;
      if (error.statusCode == 413) {
        final bool applied = _applyUploadLimitsFromApiError(error);
        if (!applied) _applyFallback413Limits();
        message =
            'Upload too large. Try up to $_maxImageSizeMbLabel MB each '
            '($_maxTotalImageUploadMbLabel MB total), then submit again.';
      }
      _showSnack(message);
    } catch (_) {
      if (!mounted) return;
      _showSnack('Failed to create post.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _resetFormToDefaults() {
    _titleController.clear();
    _descriptionController.clear();
    _priceController.clear();
    _pickedLatitude = null;
    _pickedLongitude = null;
    _pickedAddress = null;
    _pickedCity = null;
    _locationTouched = false;
    _selectedStatus = 'active';
    _selectedCondition = null;
    _pickedImages.clear();
    _imageErrorText = null;
    _autoValidateMode = AutovalidateMode.disabled;
    setState(() {});
  }

  // ── Upload limits ──────────────────────────────────────────────────────────

  Future<void> _loadUploadLimitsFromApi() async {
    final PostUploadLimits? limits =
        await _createPostApiService.fetchUploadLimits();
    if (!mounted || limits == null) return;
    _applyUploadLimits(limits);
  }

  bool _applyUploadLimitsFromApiError(ApiException error) {
    final Object? raw = error.rawError;
    if (raw is! DioException) return false;
    final PostUploadLimits? limits =
        _createPostApiService.extractUploadLimitsFromDioError(raw);
    if (limits == null) return false;
    return _applyUploadLimits(limits);
  }

  bool _applyUploadLimits(PostUploadLimits limits) {
    int nextPer = _maxImageSizeBytes;
    int nextTotal = _maxTotalImageUploadBytes;
    if ((limits.perImageBytes ?? 0) > 0) nextPer = limits.perImageBytes!;
    if ((limits.totalBytes ?? 0) > 0) nextTotal = limits.totalBytes!;
    if (nextTotal < nextPer) nextTotal = nextPer;
    if (nextPer == _maxImageSizeBytes && nextTotal == _maxTotalImageUploadBytes)
      return false;
    setState(() {
      _maxImageSizeBytes = nextPer;
      _maxTotalImageUploadBytes = nextTotal;
    });
    return true;
  }

  bool _applyFallback413Limits() => _applyUploadLimits(PostUploadLimits(
        perImageBytes: _fallback413PerImageLimitMb * _bytesPerMb,
        totalBytes: _fallback413TotalLimitMb * _bytesPerMb,
      ));

  String _formatMbLabel(int bytes) {
    final double v = bytes / _bytesPerMb;
    final int r = v.round();
    return (v - r).abs() < 0.05 ? r.toString() : v.toStringAsFixed(1);
  }

  String _normalizeDescription(String raw) {
    final String t = raw.trim();
    if (t.isEmpty) return '';
    if (t.startsWith('<')) return t;
    return '<p>${t.replaceAll('\n', '<br>')}</p>';
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FD),
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'Create Post',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: Form(
        key: _formKey,
        autovalidateMode: _autoValidateMode,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // ── Images ───────────────────────────────────────────────
              Row(
                children: <Widget>[
                  const AppFormSectionLabel(text: 'IMAGES'),
                  const Spacer(),
                  Text(
                    '${_pickedImages.length} UPLOADED',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                      color: Color(0xFF9AA0B8),
                    ),
                  ),
                ],
              ),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isBusy ? null : _pickImages,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF2F3552),
                    backgroundColor: const Color(0xFFF6F7FD),
                    side: BorderSide(
                      color: _imageErrorText == null
                          ? _fieldBorderColor
                          : AppColors.error,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  icon: const Icon(Icons.upload_outlined, size: 18),
                  label: const Text(
                    'Add Image',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              Center(
                child: Text(
                  'JPEG, PNG, WebP — max $_maxImageSizeMbLabel MB each '
                  '($_maxTotalImageUploadMbLabel MB total)',
                  style: const TextStyle(
                      color: Color(0xFF9AA0B8), fontSize: 12),
                ),
              ),
              if (_pickedImages.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                _buildImagePreviewStrip(),
              ],
              const SizedBox(height: 10),

              // ── Category warning ──────────────────────────────────────
              if (_resolvedCategoryId == null)
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF1F1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFF2CBCB)),
                  ),
                  child: const Row(
                    children: <Widget>[
                      Icon(Icons.warning_amber_rounded,
                          color: AppColors.error, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Missing category. Go back and choose one first.',
                          style: TextStyle(
                              color: AppColors.error,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),

              // ── Title ────────────────────────────────────────────────
              const AppFormSectionLabel(text: 'TITLE'),
              TextFormField(
                controller: _titleController,
                enabled: !_isBusy,
                decoration:
                    _fieldDecoration(hintText: 'e.g. iPhone 14 Pro Max'),
                validator: (v) =>
                    (v?.trim() ?? '').isEmpty ? 'Title is required' : null,
              ),
              const SizedBox(height: 10),

              // ── Description ───────────────────────────────────────────
              const AppFormSectionLabel(text: 'DESCRIPTION'),
              _buildDescriptionField(isBusy: _isBusy),
              const SizedBox(height: 8),

              // ── Price + Status ────────────────────────────────────────
              AppTwoColumnFormRow(
                gap: 10,
                left: AppLabeledFormField(
                  label: 'PRICE (\$)',
                  child: TextFormField(
                    controller: _priceController,
                    enabled: !_isBusy,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    inputFormatters: <TextInputFormatter>[
                      PriceInputUtils.decimalFormatter,
                    ],
                    decoration: _fieldDecoration(
                      hintText: '0.00',
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 4),
                    ),
                    validator: (v) =>
                        PriceInputUtils.validatePositiveRequired(
                      v,
                      requiredMessage: 'Price is required',
                      invalidMessage: 'Price must be greater than 0',
                    ),
                  ),
                ),
                right: AppLabeledFormField(
                  label: 'STATUS',
                  child: _buildDropdownField<String>(
                    value: _selectedStatus,
                    hintText: 'Active',
                    items: _statusDropdownItems,
                    onChanged: _isBusy
                        ? null
                        : (v) {
                            if (v == null) return;
                            setState(() => _selectedStatus = v);
                          },
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // ── Condition ─────────────────────────────────────────────
              AppLabeledFormField(
                label: 'CONDITION',
                child: _buildDropdownField<String>(
                  value: _selectedCondition,
                  hintText: '— Select —',
                  items: _conditionDropdownItems,
                  onChanged: _isBusy
                      ? null
                      : (v) => setState(() => _selectedCondition = v),
                ),
              ),
              const SizedBox(height: 18),

              // ── Location card ─────────────────────────────────────────
              const AppFormSectionLabel(text: 'LOCATION'),
              LocationPickerCard(
                enabled: !_isBusy,
                latitude: _pickedLatitude,
                longitude: _pickedLongitude,
                address: _pickedAddress,
                city: _pickedCity,
                onLocationPicked: _onLocationPicked,
              ),
              if (_locationTouched && !_hasLocation)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 4),
                  child: Text(
                    'Please set a location on the map',
                    style: TextStyle(
                        color: AppColors.error, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 24),

              // ── Buttons ───────────────────────────────────────────────
              Row(
                children: <Widget>[
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isBusy ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accentColor,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            _accentColor.withValues(alpha: 0.45),
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        padding:
                            const EdgeInsets.symmetric(vertical: 15),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Text(
                              'Create Post',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 120,
                    child: OutlinedButton(
                      onPressed: _isBusy
                          ? null
                          : () {
                              if (Navigator.of(context).canPop()) {
                                Navigator.of(context).maybePop();
                                return;
                              }
                              _resetFormToDefaults();
                            },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF2F3552),
                        side: const BorderSide(color: _fieldBorderColor),
                        backgroundColor: const Color(0xFFF0F1F8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        padding:
                            const EdgeInsets.symmetric(vertical: 15),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImagePreviewStrip() {
    return SizedBox(
      height: 82,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _pickedImages.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) =>
            _buildImageThumbnail(image: _pickedImages[index], index: index),
      ),
    );
  }

  Widget _buildImageThumbnail({required XFile image, required int index}) {
    return Stack(
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 82,
            height: 82,
            decoration: BoxDecoration(
              color: const Color(0xFFE5E7EB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFD3D9DF)),
            ),
            child: Image.file(
              File(image.path),
              width: 82,
              height: 82,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.image_not_supported_outlined),
            ),
          ),
        ),
        Positioned(
          top: 3,
          right: 3,
          child: GestureDetector(
            onTap: _isBusy
                ? null
                : () => setState(() => _pickedImages.removeAt(index)),
            child: Container(
              decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: Colors.black54),
              padding: const EdgeInsets.all(3),
              child:
                  const Icon(Icons.close, size: 12, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDescriptionField({required bool isBusy}) {
    return TextFormField(
      controller: _descriptionController,
      enabled: !isBusy,
      minLines: 5,
      maxLines: 8,
      decoration: _fieldDecoration(
        hintText: 'Describe your product',
        contentPadding: const EdgeInsets.all(10),
      ),
      validator: (v) =>
          (v?.trim() ?? '').isEmpty ? 'Description is required' : null,
    );
  }

  InputDecoration _fieldDecoration({
    required String hintText,
    Widget? suffixIcon,
    EdgeInsetsGeometry? contentPadding,
  }) {
    return InputDecoration(
      hintText: hintText,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white,
      hintStyle: const TextStyle(color: _fieldHintColor, fontSize: 15),
      contentPadding: contentPadding ??
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _fieldBorderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _fieldBorderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _accentColor, width: 1.2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.error, width: 1.2),
      ),
    );
  }

  Widget _buildDropdownField<T>({
    required T? value,
    required String hintText,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?>? onChanged,
  }) {
    final bool isEnabled = onChanged != null;
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      icon: const Icon(Icons.keyboard_arrow_down_rounded,
          color: Color(0xFF7E86A4)),
      decoration: _fieldDecoration(
        hintText: hintText,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      ).copyWith(
        fillColor: isEnabled ? Colors.white : const Color(0xFFF2F4FA),
      ),
      borderRadius: BorderRadius.circular(14),
      dropdownColor: Colors.white,
      hint: Text(hintText, style: const TextStyle(color: _fieldHintColor)),
      style: const TextStyle(
          color: Color(0xFF303854),
          fontSize: 16,
          fontWeight: FontWeight.w500),
      items: items,
      onChanged: onChanged,
    );
  }
}