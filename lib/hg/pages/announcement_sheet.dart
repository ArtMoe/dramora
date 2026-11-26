import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/hg_announcement.dart';
import '../theme/hg_theme.dart';
import '../utils/hg_format.dart';
import '../widgets/hg_adaptive_sheet.dart';

enum HgAnnouncementDecision { today, acknowledge }

Future<HgAnnouncementDecision?> showHgAnnouncementSheet(
  BuildContext context,
  HgAnnouncement announcement, {
  bool handled = false,
}) {
  return showHgAdaptiveSheetBuilder<HgAnnouncementDecision>(
    context,
    childScrollable: true,
    initialSize: 0.62,
    minSize: 0.34,
    maxSize: 0.9,
    barrierColor: Colors.black.withValues(alpha: 0.44),
    builder: (_) =>
        _HgAnnouncementSheet(announcement: announcement, handled: handled),
  );
}

class _HgAnnouncementSheet extends StatefulWidget {
  const _HgAnnouncementSheet({
    required this.announcement,
    required this.handled,
  });

  final HgAnnouncement announcement;
  final bool handled;

  @override
  State<_HgAnnouncementSheet> createState() => _HgAnnouncementSheetState();
}

class _HgAnnouncementSheetState extends State<_HgAnnouncementSheet> {
  bool _opening = false;

  Future<void> _openAction() async {
    final action = widget.announcement.action;
    if (action == null || _opening) return;
    setState(() => _opening = true);
    try {
      final uri = Uri.parse(action.url);
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        showHgSnack(context, '暂时无法打开链接，请稍后重试');
      }
    } catch (_) {
      if (mounted) showHgSnack(context, '暂时无法打开链接，请稍后重试');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final announcement = widget.announcement;
    final accent = _accentFor(announcement.type);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 2, 22, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(
                    _iconFor(announcement.type),
                    color: accent,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '果幕公告',
                            style: TextStyle(
                              color: context.hgOnSurface,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (announcement.isImportant) ...[
                            const SizedBox(width: 7),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.13),
                                borderRadius: BorderRadius.circular(7),
                              ),
                              child: Text(
                                '重要',
                                style: TextStyle(
                                  color: accent,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _formatDate(announcement.publishedAt.toLocal()),
                        style: TextStyle(
                          color: context.hgSubtle,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              announcement.title,
              style: TextStyle(
                color: context.hgOnSurface,
                fontSize: 25,
                height: 1.2,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.7,
              ),
            ),
            const SizedBox(height: 13),
            SelectionArea(
              child: Text(
                announcement.body,
                style: TextStyle(
                  color: context.hgOnSurface.withValues(alpha: 0.78),
                  fontSize: 14,
                  height: 1.72,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            if (announcement.action != null) ...[
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: _opening ? null : _openAction,
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.hgOnSurface,
                  side: BorderSide(color: context.hgLine),
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: _opening
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.open_in_new_rounded, size: 18),
                label: Text(announcement.action!.label),
              ),
            ],
            const SizedBox(height: 22),
            if (widget.handled)
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('关闭'),
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(
                        context,
                      ).pop(HgAnnouncementDecision.today),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: context.hgOnSurface,
                        side: BorderSide(color: context.hgLine),
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('今日不再提醒'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(
                        context,
                      ).pop(HgAnnouncementDecision.acknowledge),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('下次再通知我'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              Text(
                '“下次再通知我”只会在发布新公告时再次提醒。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.hgSubtle,
                  fontSize: 10.5,
                  height: 1.45,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

IconData _iconFor(HgAnnouncementType type) => switch (type) {
  HgAnnouncementType.notice => Icons.campaign_rounded,
  HgAnnouncementType.activity => Icons.celebration_rounded,
  HgAnnouncementType.project => Icons.rocket_launch_rounded,
  HgAnnouncementType.maintenance => Icons.construction_rounded,
};

Color _accentFor(HgAnnouncementType type) => switch (type) {
  HgAnnouncementType.notice => HgColors.orange,
  HgAnnouncementType.activity => HgColors.gold,
  HgAnnouncementType.project => const Color(0xFF4D7CFE),
  HgAnnouncementType.maintenance => const Color(0xFF8A8A8E),
};

String _formatDate(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}.$month.$day';
}
