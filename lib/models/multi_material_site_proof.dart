/// Models for `GET/POST /API/site_proof/multi_material/...`.

class MultiMaterialSiteProofSession {
  final int indentId;
  final int itemRunId;
  final String projectName;
  final String projectNumber;
  final String poNumber;
  final String siteProofFlow;
  final int materialCount;
  final List<MultiMaterialLine> materials;
  final MultiMaterialCommonFields common;
  final MultiMaterialSiteLocation? siteLocation;
  final int nearSiteRadiusMeters;
  final bool siteLocationAvailable;
  final Map<String, dynamic> raw;

  const MultiMaterialSiteProofSession({
    required this.indentId,
    required this.itemRunId,
    required this.projectName,
    required this.projectNumber,
    required this.poNumber,
    required this.siteProofFlow,
    required this.materialCount,
    required this.materials,
    required this.common,
    this.siteLocation,
    this.nearSiteRadiusMeters = 500,
    this.siteLocationAvailable = false,
    this.raw = const {},
  });

  factory MultiMaterialSiteProofSession.fromJson(Map<String, dynamic> json) {
    final materialsRaw = json['materials'];
    final materials = <MultiMaterialLine>[];
    if (materialsRaw is List) {
      for (final row in materialsRaw) {
        if (row is Map) {
          materials.add(
            MultiMaterialLine.fromJson(Map<String, dynamic>.from(row)),
          );
        }
      }
    }

    final commonRaw = json['common'];
    final common = commonRaw is Map
        ? MultiMaterialCommonFields.fromJson(
            Map<String, dynamic>.from(commonRaw),
          )
        : MultiMaterialCommonFields.fromJson(json);

    final siteRaw =
        json['site_location'] ?? json['project_site_location'] ?? json['site'];
    MultiMaterialSiteLocation? site;
    if (siteRaw is Map) {
      site = MultiMaterialSiteLocation.fromJson(
        Map<String, dynamic>.from(siteRaw),
      );
    } else if (siteRaw is String && siteRaw.trim().isNotEmpty) {
      site = MultiMaterialSiteLocation.tryParse(siteRaw);
    }

    final availableRaw = json['site_location_available'];
    final available = availableRaw == null
        ? site != null
        : _truthy(availableRaw);

    return MultiMaterialSiteProofSession(
      indentId: _asInt(json['indent_id']),
      itemRunId: _asInt(
        json['item_run_id'] ?? json['workflow_item_run_id'],
      ),
      projectName: _asString(json['project_name']),
      projectNumber: _asString(json['project_number']),
      poNumber: _asString(json['po_number']),
      siteProofFlow: _asString(json['site_proof_flow']),
      materialCount: () {
        final count = _asInt(json['material_count']);
        return count > 0 ? count : materials.length;
      }(),
      materials: materials,
      common: common,
      siteLocation: site,
      nearSiteRadiusMeters: () {
        final radius = _asInt(json['near_site_radius_meters']);
        return radius > 0 ? radius : 500;
      }(),
      siteLocationAvailable: available,
      raw: Map<String, dynamic>.from(json),
    );
  }

  MultiMaterialSiteProofSession copyWith({
    List<MultiMaterialLine>? materials,
    MultiMaterialCommonFields? common,
  }) {
    return MultiMaterialSiteProofSession(
      indentId: indentId,
      itemRunId: itemRunId,
      projectName: projectName,
      projectNumber: projectNumber,
      poNumber: poNumber,
      siteProofFlow: siteProofFlow,
      materialCount: materialCount,
      materials: materials ?? this.materials,
      common: common ?? this.common,
      siteLocation: siteLocation,
      nearSiteRadiusMeters: nearSiteRadiusMeters,
      siteLocationAvailable: siteLocationAvailable,
      raw: raw,
    );
  }
}

class MultiMaterialLine {
  final String materialKey;
  final String material;
  final String unit;
  final String orderedQuantity;
  final String previouslyReceivedQuantity;
  final String remainingQuantity;
  final bool selected;
  final String quantityReceivedToday;
  final int photoCount;
  final int videoCount;
  final String comment;
  final bool completed;
  final int? minPhotos;
  final int? maxPhotos;
  final bool requirePhotos;
  final bool requireVideo;
  final String? thumbnailUrl;
  final Map<String, dynamic> raw;

  const MultiMaterialLine({
    required this.materialKey,
    required this.material,
    required this.unit,
    required this.orderedQuantity,
    required this.previouslyReceivedQuantity,
    required this.remainingQuantity,
    this.selected = false,
    this.quantityReceivedToday = '',
    this.photoCount = 0,
    this.videoCount = 0,
    this.comment = '',
    this.completed = false,
    this.minPhotos,
    this.maxPhotos,
    this.requirePhotos = true,
    this.requireVideo = false,
    this.thumbnailUrl,
    this.raw = const {},
  });

  factory MultiMaterialLine.fromJson(Map<String, dynamic> json) {
    final requirePhotosRaw = json['require_photos'] ?? json['photos_required'];
    final requireVideoRaw = json['require_video'] ?? json['video_required'];
    final maxPhotos = _nullableInt(json['max_photos'] ?? json['max_photo_count']);
    final minPhotos = _nullableInt(json['min_photos'] ?? json['min_photo_count']);

    return MultiMaterialLine(
      materialKey: _asString(
        json['material_key'] ?? json['key'] ?? json['id'],
      ),
      material: _asString(json['material'] ?? json['name'] ?? json['title']),
      unit: _asString(json['unit']),
      orderedQuantity: _asString(
        json['ordered_quantity'] ?? json['quantity'] ?? json['ordered'],
      ),
      previouslyReceivedQuantity: _asString(
        json['previously_received_quantity'] ??
            json['already_received'] ??
            json['received_quantity'],
      ),
      remainingQuantity: _asString(
        json['remaining_quantity'] ?? json['remaining'],
      ),
      selected: _truthy(json['selected']),
      quantityReceivedToday: _asString(
        json['quantity_received_today'] ?? json['received_today'],
      ),
      photoCount: _asInt(json['photo_count']),
      videoCount: _asInt(json['video_count']),
      comment: _asString(json['comment'] ?? json['material_comment']),
      completed: _truthy(json['completed'] ?? json['is_complete']),
      minPhotos: minPhotos,
      maxPhotos: maxPhotos ?? 5,
      requirePhotos: requirePhotosRaw == null ? true : _truthy(requirePhotosRaw),
      requireVideo:
          requireVideoRaw == null ? false : _truthy(requireVideoRaw),
      thumbnailUrl: _asString(json['thumbnail_url'] ?? json['image_url']),
      raw: Map<String, dynamic>.from(json),
    );
  }

  MultiMaterialLine copyWith({
    bool? selected,
    String? quantityReceivedToday,
    int? photoCount,
    int? videoCount,
    String? comment,
    bool? completed,
    String? remainingQuantity,
  }) {
    return MultiMaterialLine(
      materialKey: materialKey,
      material: material,
      unit: unit,
      orderedQuantity: orderedQuantity,
      previouslyReceivedQuantity: previouslyReceivedQuantity,
      remainingQuantity: remainingQuantity ?? this.remainingQuantity,
      selected: selected ?? this.selected,
      quantityReceivedToday:
          quantityReceivedToday ?? this.quantityReceivedToday,
      photoCount: photoCount ?? this.photoCount,
      videoCount: videoCount ?? this.videoCount,
      comment: comment ?? this.comment,
      completed: completed ?? this.completed,
      minPhotos: minPhotos,
      maxPhotos: maxPhotos,
      requirePhotos: requirePhotos,
      requireVideo: requireVideo,
      thumbnailUrl: thumbnailUrl,
      raw: raw,
    );
  }

  double? get remainingAsNumber => _asDouble(remainingQuantity);

  double? get orderedAsNumber => _asDouble(orderedQuantity);

  double? get previouslyReceivedAsNumber =>
      _asDouble(previouslyReceivedQuantity);

  double? get quantityTodayAsNumber => _asDouble(quantityReceivedToday);

  int get effectiveMinPhotos {
    if (!requirePhotos) return 0;
    return (minPhotos ?? 1).clamp(0, maxPhotos ?? 5);
  }

  int get effectiveMaxPhotos => (maxPhotos ?? 5).clamp(1, 20);
}

class MultiMaterialCommonFields {
  final String measurement;
  final String measurementUnit;
  final String vehicleNumber;
  final String vehicleType;
  final String driverName;
  final String driverPhone;
  final String vehicleComment;
  final String siteComment;
  final String weight;

  const MultiMaterialCommonFields({
    this.measurement = '',
    this.measurementUnit = '',
    this.vehicleNumber = '',
    this.vehicleType = '',
    this.driverName = '',
    this.driverPhone = '',
    this.vehicleComment = '',
    this.siteComment = '',
    this.weight = '',
  });

  factory MultiMaterialCommonFields.fromJson(Map<String, dynamic> json) {
    return MultiMaterialCommonFields(
      measurement: _asString(json['measurement']),
      measurementUnit: _asString(
        json['measurement_unit'] ?? json['unit_of_measurement'],
      ),
      vehicleNumber: _asString(json['vehicle_number']),
      vehicleType: _asString(json['vehicle_type']),
      driverName: _asString(json['driver_name']),
      driverPhone: _asString(json['driver_phone']),
      vehicleComment: _asString(
        json['vehicle_comment'] ?? json['vehicle_comments'],
      ),
      siteComment: _asString(
        json['site_comment'] ?? json['comment'] ?? json['comments'],
      ),
      weight: _asString(json['weight']),
    );
  }

  MultiMaterialCommonFields copyWith({
    String? measurement,
    String? measurementUnit,
    String? vehicleNumber,
    String? vehicleType,
    String? driverName,
    String? driverPhone,
    String? vehicleComment,
    String? siteComment,
    String? weight,
  }) {
    return MultiMaterialCommonFields(
      measurement: measurement ?? this.measurement,
      measurementUnit: measurementUnit ?? this.measurementUnit,
      vehicleNumber: vehicleNumber ?? this.vehicleNumber,
      vehicleType: vehicleType ?? this.vehicleType,
      driverName: driverName ?? this.driverName,
      driverPhone: driverPhone ?? this.driverPhone,
      vehicleComment: vehicleComment ?? this.vehicleComment,
      siteComment: siteComment ?? this.siteComment,
      weight: weight ?? this.weight,
    );
  }

  Map<String, dynamic> toRequestBody({bool includeEmpty = false}) {
    final map = <String, dynamic>{
      'measurement': measurement,
      'measurement_unit': measurementUnit,
      'vehicle_number': vehicleNumber,
      'vehicle_type': vehicleType,
      'driver_name': driverName,
      'driver_phone': driverPhone,
      'vehicle_comment': vehicleComment,
      'site_comment': siteComment,
      'weight': weight,
    };
    if (includeEmpty) return map;
    map.removeWhere((_, value) => value.toString().trim().isEmpty);
    return map;
  }
}

class MultiMaterialSiteLocation {
  final double latitude;
  final double longitude;

  const MultiMaterialSiteLocation({
    required this.latitude,
    required this.longitude,
  });

  factory MultiMaterialSiteLocation.fromJson(Map<String, dynamic> json) {
    return MultiMaterialSiteLocation(
      latitude: _asDouble(json['latitude'] ?? json['lat']) ?? 0,
      longitude: _asDouble(json['longitude'] ?? json['lng'] ?? json['lon']) ?? 0,
    );
  }

  static MultiMaterialSiteLocation? tryParse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final parts = trimmed.split(RegExp(r'[,;\s]+'));
    if (parts.length < 2) return null;
    final lat = double.tryParse(parts[0]);
    final lng = double.tryParse(parts[1]);
    if (lat == null || lng == null) return null;
    return MultiMaterialSiteLocation(latitude: lat, longitude: lng);
  }
}

class MultiMaterialSubmitResult {
  final bool success;
  final String message;
  final int indentId;
  final int itemRunId;
  final String deliveryId;
  final bool hasRemainingMaterials;
  final Map<String, dynamic>? review;
  final Map<String, dynamic> raw;

  const MultiMaterialSubmitResult({
    required this.success,
    required this.message,
    required this.indentId,
    required this.itemRunId,
    required this.deliveryId,
    required this.hasRemainingMaterials,
    this.review,
    this.raw = const {},
  });

  factory MultiMaterialSubmitResult.fromJson(Map<String, dynamic> json) {
    final reviewRaw = json['review'];
    return MultiMaterialSubmitResult(
      success: _truthy(json['success']) || json['success'] == null,
      message: _asString(json['message']),
      indentId: _asInt(json['indent_id']),
      itemRunId: _asInt(json['item_run_id']),
      deliveryId: _asString(json['delivery_id']),
      hasRemainingMaterials: _truthy(json['has_remaining_materials']),
      review: reviewRaw is Map
          ? Map<String, dynamic>.from(reviewRaw)
          : null,
      raw: Map<String, dynamic>.from(json),
    );
  }
}

class MultiMaterialSiteProofException implements Exception {
  final String message;
  final int? statusCode;

  const MultiMaterialSiteProofException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

String _asString(dynamic value) {
  if (value == null) return '';
  final text = value.toString().trim();
  if (text.isEmpty || text.toLowerCase() == 'null') return '';
  return text;
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int? _nullableInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString().trim());
}

double? _asDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  final text = value.toString().trim().replaceAll(',', '');
  if (text.isEmpty) return null;
  return double.tryParse(text);
}

bool _truthy(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value?.toString().trim().toLowerCase() ?? '';
  return text == '1' || text == 'true' || text == 'yes';
}
