import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:EMART24/features/sell/presentation/location_picker_screen.dart';

/// Inline location card that matches the screenshot UI:
///   ┌─────────────────────────────┐
///   │ Location   [city / district]│
///   ├─────────────────────────────┤
///   │ Address    [full address]   │
///   ├─────────────────────────────┤
///   │  [mini map]                 │
///   │  ┌──────────────────────┐   │
///   │  │ 📍 Set location on Map│  │
///   │  └──────────────────────┘   │
///   └─────────────────────────────┘
class LocationPickerCard extends StatelessWidget {
  const LocationPickerCard({
    super.key,
    required this.onLocationPicked,
    this.latitude,
    this.longitude,
    this.address,
    this.city,
    this.enabled = true,
  });

  final double? latitude;
  final double? longitude;
  final String? address;

  /// Short city / district label shown in the top "Location" row.
  final String? city;

  final bool enabled;
  final ValueChanged<LocationPickerResult> onLocationPicked;

  bool get _hasPick => latitude != null && longitude != null;

  Future<void> _openPicker(BuildContext context) async {
    if (!enabled) return;
    final LatLng? initial =
        _hasPick ? LatLng(latitude!, longitude!) : null;

    final LocationPickerResult? result =
        await Navigator.of(context).push<LocationPickerResult>(
      MaterialPageRoute<LocationPickerResult>(
        builder: (_) => LocationPickerScreen(initialLocation: initial),
      ),
    );
    if (result != null) {
      onLocationPicked(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        // ── Location row ────────────────────────────────────────────────
        _Field(
          label: 'Location',
          value: city ?? (_hasPick ? _shortCoord() : null),
          placeholder: 'Not set',
          roundTop: true,
          roundBottom: false,
        ),

        const SizedBox(height: 1),

        // ── Address row ─────────────────────────────────────────────────
        _Field(
          label: 'Address',
          value: address,
          placeholder: 'Tap map to pick location',
          roundTop: false,
          roundBottom: false,
        ),

        // ── Mini map ────────────────────────────────────────────────────
        ClipRRect(
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(14),
            bottomRight: Radius.circular(14),
          ),
          child: SizedBox(
            height: 180,
            child: Stack(
              children: <Widget>[
                // Map tiles
                _hasPick
                    ? _MiniMap(latitude: latitude!, longitude: longitude!)
                    : _PlaceholderMap(),

                // Centre pin (only when a location is picked)
                if (_hasPick)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 24),
                      child: Icon(
                        Icons.location_pin,
                        color: Colors.red,
                        size: 36,
                      ),
                    ),
                  ),

                // "Set location on Map" button overlay
                Center(
                  child: GestureDetector(
                    onTap: () => _openPicker(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const <BoxShadow>[
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          // Google Maps-style coloured pin icon
                          const _ColoredMapPin(size: 28),
                          const SizedBox(width: 12),
                          Text(
                            _hasPick
                                ? 'Change location on Map'
                                : 'Set location on Map',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF202020),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _shortCoord() =>
      '${latitude!.toStringAsFixed(4)}, ${longitude!.toStringAsFixed(4)}';
}

// ── Private helpers ────────────────────────────────────────────────────────

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.placeholder,
    required this.roundTop,
    required this.roundBottom,
    this.value,
  });

  final String label;
  final String? value;
  final String placeholder;
  final bool roundTop;
  final bool roundBottom;

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.only(
      topLeft: roundTop ? const Radius.circular(14) : Radius.zero,
      topRight: roundTop ? const Radius.circular(14) : Radius.zero,
      bottomLeft: roundBottom ? const Radius.circular(14) : Radius.zero,
      bottomRight: roundBottom ? const Radius.circular(14) : Radius.zero,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2D3E),
        borderRadius: radius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF8E95B1),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  value ?? placeholder,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: value != null
                        ? Colors.white
                        : const Color(0xFF5A6080),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (label == 'Location')
                const Icon(
                  Icons.keyboard_arrow_down,
                  color: Color(0xFF8E95B1),
                  size: 20,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniMap extends StatelessWidget {
  const _MiniMap({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      options: MapOptions(
        initialCenter: LatLng(latitude, longitude),
        initialZoom: 15,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.none, // disable all gestures on mini map
        ),
      ),
      children: <Widget>[
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.yourapp.emart24',
        ),
      ],
    );
  }
}

class _PlaceholderMap extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFD6E4F0),
      child: const Center(
        child: Icon(Icons.map_outlined, size: 48, color: Color(0xFFAEC6D8)),
      ),
    );
  }
}

/// Recreates the Google Maps-style 4-colour teardrop pin using plain Canvas.
class _ColoredMapPin extends StatelessWidget {
  const _ColoredMapPin({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _PinPainter(),
    );
  }
}

class _PinPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double cx = size.width / 2;
    final double r = size.width * 0.42;
    final Offset centre = Offset(cx, r);

    // Four quadrant colours (clockwise from top-left)
    const List<Color> colors = <Color>[
      Color(0xFF4285F4), // blue   TL
      Color(0xFFEA4335), // red    TR
      Color(0xFFFFBB00), // yellow BL
      Color(0xFF34A853), // green  BR
    ];

    for (int i = 0; i < 4; i++) {
      final double startAngle = (i * 90 - 90) * (3.14159265 / 180);
      final double sweepAngle = 90 * (3.14159265 / 180);
      final Paint p = Paint()..color = colors[i];
      canvas.drawArc(
        Rect.fromCircle(center: centre, radius: r),
        startAngle,
        sweepAngle,
        true,
        p,
      );
    }

    // White inner circle
    canvas.drawCircle(centre, r * 0.42, Paint()..color = Colors.white);

    // Teardrop tail
    final Path tail = Path()
      ..moveTo(cx - r * 0.28, centre.dy + r * 0.55)
      ..lineTo(cx, size.height)
      ..lineTo(cx + r * 0.28, centre.dy + r * 0.55)
      ..close();
    canvas.drawPath(tail, Paint()..color = const Color(0xFFEA4335));
  }

  @override
  bool shouldRepaint(_PinPainter oldDelegate) => false;
}