import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

/// Returned when the user confirms a location.
class LocationPickerResult {
  const LocationPickerResult({
    required this.latitude,
    required this.longitude,
    this.address,
  });

  /// Maps directly to [CreatePostApiService.createPost] `latitude` param.
  final double latitude;

  /// Maps directly to [CreatePostApiService.createPost] `longitude` param.
  final double longitude;

  /// Maps directly to [CreatePostApiService.createPost] `location` param.
  final String? address;
}

/// Full-screen map picker powered by OpenStreetMap — no API key required.
///
/// Usage:
/// ```dart
/// final LocationPickerResult? result =
///     await Navigator.of(context).push<LocationPickerResult>(
///   MaterialPageRoute(builder: (_) => const LocationPickerScreen()),
/// );
/// if (result != null) {
///   await apiService.createPost(
///     ...
///     location:  result.address,
///     latitude:  result.latitude,
///     longitude: result.longitude,
///   );
/// }
/// ```
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key, this.initialLocation});

  /// Pre-select a position (e.g. when editing an existing post).
  final LatLng? initialLocation;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  // Default centre: Phnom Penh, Cambodia
  static const LatLng _defaultLocation = LatLng(11.5564, 104.9282);

  late final MapController _mapController;
  late LatLng _pickedLocation;

  String? _pickedAddress;
  bool _isLoadingAddress = false;
  bool _isLoadingCurrentLocation = false;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _pickedLocation = widget.initialLocation ?? _defaultLocation;
    _fetchAddress(_pickedLocation);
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  // ── Address reverse-geocoding ──────────────────────────────────────────────

  Future<void> _fetchAddress(LatLng position) async {
    setState(() => _isLoadingAddress = true);
    try {
      final List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (!mounted) return;
      if (placemarks.isNotEmpty) {
        final Placemark p = placemarks.first;
        final List<String> parts = <String>[
          if (p.street?.isNotEmpty == true) p.street!,
          if (p.subAdministrativeArea?.isNotEmpty == true)
            p.subAdministrativeArea!,
          if (p.administrativeArea?.isNotEmpty == true) p.administrativeArea!,
          if (p.country?.isNotEmpty == true) p.country!,
        ];
        setState(() {
          _pickedAddress =
              parts.isNotEmpty ? parts.join(', ') : 'Unknown location';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _pickedAddress = 'Could not resolve address');
    } finally {
      if (mounted) setState(() => _isLoadingAddress = false);
    }
  }

  // ── GPS current location ───────────────────────────────────────────────────

  Future<void> _goToCurrentLocation() async {
    setState(() => _isLoadingCurrentLocation = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permission is permanently denied.'),
            ),
          );
        }
        return;
      }

      final Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final LatLng current = LatLng(pos.latitude, pos.longitude);
      _mapController.move(current, 16);
      setState(() => _pickedLocation = current);
      await _fetchAddress(current);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not get location: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingCurrentLocation = false);
    }
  }

  // ── Confirm & return result ────────────────────────────────────────────────

  void _confirmLocation() {
    Navigator.of(context).pop(
      LocationPickerResult(
        latitude: _pickedLocation.latitude,
        longitude: _pickedLocation.longitude,
        address: _pickedAddress,
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pick Location'),
        actions: <Widget>[
          TextButton(
            onPressed: _confirmLocation,
            child: const Text(
              'Confirm',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: Stack(
        children: <Widget>[
          // ── OpenStreetMap tile layer (free, no API key) ──────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _pickedLocation,
              initialZoom: 14,
              onPositionChanged: (MapCamera camera, bool hasGesture) {
                if (hasGesture) {
                  setState(() => _pickedLocation = camera.center);
                }
              },
              onMapEvent: (MapEvent event) {
                // Reverse-geocode only after the user stops dragging.
                if (event is MapEventMoveEnd) {
                  _fetchAddress(_pickedLocation);
                }
              },
            ),
            children: <Widget>[
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                // Replace with your app's package name — required by OSM policy.
                userAgentPackageName: 'com.yourapp.emart24',
              ),
            ],
          ),

          // ── Centre pin ───────────────────────────────────────────────────
          const Center(
            child: Padding(
              padding: EdgeInsets.only(bottom: 40),
              child: Icon(Icons.location_pin, color: Colors.red, size: 48),
            ),
          ),

          // ── My-location FAB ──────────────────────────────────────────────
          Positioned(
            right: 16,
            bottom: 220,
            child: FloatingActionButton.small(
              heroTag: 'myLocation',
              onPressed: _isLoadingCurrentLocation
                  ? null
                  : _goToCurrentLocation,
              child: _isLoadingCurrentLocation
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location),
            ),
          ),

          // ── Address card ─────────────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const <BoxShadow>[
                  BoxShadow(color: Colors.black26, blurRadius: 8),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'Selected Location',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _isLoadingAddress
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          _pickedAddress ?? 'Move map to pick a location',
                          style: const TextStyle(color: Colors.black54),
                        ),
                  const SizedBox(height: 4),
                  Text(
                    'Lat: ${_pickedLocation.latitude.toStringAsFixed(6)}  '
                    'Lng: ${_pickedLocation.longitude.toStringAsFixed(6)}',
                    style:
                        const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _confirmLocation,
                      icon: const Icon(Icons.check),
                      label: const Text('Confirm Location'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}