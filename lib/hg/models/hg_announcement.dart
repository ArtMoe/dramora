import 'dart:convert';

enum HgAnnouncementType {
  notice,
  activity,
  project,
  maintenance;

  static HgAnnouncementType parse(Object? value) {
    final name = value?.toString().trim().toLowerCase() ?? '';
    for (final type in values) {
      if (type.name == name) return type;
    }
    throw FormatException('未知公告类型：$name');
  }
}

enum HgAnnouncementPriority {
  normal,
  important;

  static HgAnnouncementPriority parse(Object? value) {
    final name = value?.toString().trim().toLowerCase() ?? '';
    for (final priority in values) {
      if (priority.name == name) return priority;
    }
    throw FormatException('未知公告优先级：$name');
  }
}

class HgAnnouncementAction {
  const HgAnnouncementAction({required this.label, required this.url});

  final String label;
  final String url;

  factory HgAnnouncementAction.fromJson(Map<String, dynamic> json) {
    final label = (json['label']?.toString() ?? '').trim();
    final url = (json['url']?.toString() ?? '').trim();
    final uri = Uri.tryParse(url);
    if (label.isEmpty || label.length > 24) {
      throw const FormatException('公告按钮名称无效');
    }
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const FormatException('公告按钮链接必须使用 HTTPS');
    }
    return HgAnnouncementAction(label: label, url: uri.toString());
  }

  Map<String, dynamic> toJson() => {'label': label, 'url': url};
}

class HgAnnouncement {
  const HgAnnouncement({
    required this.id,
    required this.type,
    required this.priority,
    required this.title,
    required this.body,
    required this.publishedAt,
    this.expiresAt,
    this.action,
  });

  static final RegExp _idPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$');

  final String id;
  final HgAnnouncementType type;
  final HgAnnouncementPriority priority;
  final String title;
  final String body;
  final DateTime publishedAt;
  final DateTime? expiresAt;
  final HgAnnouncementAction? action;

  bool get isImportant => priority == HgAnnouncementPriority.important;

  bool isPublishedAt(DateTime now) => !publishedAt.isAfter(now.toUtc());

  bool isExpiredAt(DateTime now) {
    final expiry = expiresAt;
    return expiry != null && !expiry.isAfter(now.toUtc());
  }

  bool isActiveAt(DateTime now) => isPublishedAt(now) && !isExpiredAt(now);

  factory HgAnnouncement.fromJson(Map<String, dynamic> json) {
    final id = (json['id']?.toString() ?? '').trim();
    if (!_idPattern.hasMatch(id)) {
      throw const FormatException('公告 ID 无效');
    }

    final title = (json['title']?.toString() ?? '').trim();
    if (title.isEmpty || title.length > 120) {
      throw const FormatException('公告标题无效');
    }

    final body = (json['body']?.toString() ?? '').trim();
    if (body.isEmpty || body.length > 8000) {
      throw const FormatException('公告正文无效');
    }

    final publishedAt = DateTime.tryParse(
      json['published_at']?.toString() ?? '',
    )?.toUtc();
    if (publishedAt == null) {
      throw const FormatException('公告发布时间无效');
    }

    final rawExpiresAt = json['expires_at'];
    DateTime? expiresAt;
    if (rawExpiresAt != null && rawExpiresAt.toString().trim().isNotEmpty) {
      expiresAt = DateTime.tryParse(rawExpiresAt.toString())?.toUtc();
      if (expiresAt == null || !expiresAt.isAfter(publishedAt)) {
        throw const FormatException('公告过期时间无效');
      }
    }

    final rawAction = json['action'];
    HgAnnouncementAction? action;
    if (rawAction != null) {
      if (rawAction is! Map) throw const FormatException('公告按钮无效');
      action = HgAnnouncementAction.fromJson(
        Map<String, dynamic>.from(rawAction),
      );
    }

    return HgAnnouncement(
      id: id,
      type: HgAnnouncementType.parse(json['type']),
      priority: HgAnnouncementPriority.parse(json['priority'] ?? 'normal'),
      title: title,
      body: body,
      publishedAt: publishedAt,
      expiresAt: expiresAt,
      action: action,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'priority': priority.name,
    'title': title,
    'body': body,
    'published_at': publishedAt.toIso8601String(),
    'expires_at': expiresAt?.toIso8601String(),
    'action': action?.toJson(),
  };
}

class HgAnnouncementFeed {
  const HgAnnouncementFeed({
    required this.updatedAt,
    required this.announcements,
  });

  static const schemaVersion = 1;
  static const maxAnnouncements = 50;

  final DateTime updatedAt;
  final List<HgAnnouncement> announcements;

  factory HgAnnouncementFeed.empty() => HgAnnouncementFeed(
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    announcements: const [],
  );

  factory HgAnnouncementFeed.fromJsonString(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) throw const FormatException('公告文件格式无效');
    return HgAnnouncementFeed.fromJson(Map<String, dynamic>.from(decoded));
  }

  factory HgAnnouncementFeed.fromJson(Map<String, dynamic> json) {
    final version = (json['schema_version'] as num?)?.toInt();
    if (version != schemaVersion) {
      throw const FormatException('不支持此公告文件版本');
    }

    final updatedAt = DateTime.tryParse(
      json['updated_at']?.toString() ?? '',
    )?.toUtc();
    if (updatedAt == null) throw const FormatException('公告更新时间无效');

    final rawItems = json['announcements'];
    if (rawItems is! List || rawItems.length > maxAnnouncements) {
      throw const FormatException('公告列表无效');
    }

    final ids = <String>{};
    final items = <HgAnnouncement>[];
    for (final rawItem in rawItems) {
      if (rawItem is! Map) throw const FormatException('公告条目无效');
      final item = HgAnnouncement.fromJson(Map<String, dynamic>.from(rawItem));
      if (!ids.add(item.id)) throw const FormatException('公告 ID 重复');
      items.add(item);
    }
    items.sort((left, right) => right.publishedAt.compareTo(left.publishedAt));
    return HgAnnouncementFeed(
      updatedAt: updatedAt,
      announcements: List.unmodifiable(items),
    );
  }

  Map<String, dynamic> toJson() => {
    'schema_version': schemaVersion,
    'updated_at': updatedAt.toIso8601String(),
    'announcements': announcements
        .map((announcement) => announcement.toJson())
        .toList(growable: false),
  };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());
}
