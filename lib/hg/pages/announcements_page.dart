import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/hg_announcement.dart';
import '../services/hg_announcement_service.dart';
import '../theme/hg_theme.dart';
import '../widgets/hg_refresh_indicator.dart';
import 'announcement_sheet.dart';

class AnnouncementsPage extends StatefulWidget {
  const AnnouncementsPage({super.key});

  @override
  State<AnnouncementsPage> createState() => _AnnouncementsPageState();
}

class _AnnouncementsPageState extends State<AnnouncementsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(context.read<HgAnnouncementController>().refreshIfStale());
    });
  }

  Future<void> _refresh() async {
    await context.read<HgAnnouncementController>().refresh(force: true);
  }

  Future<void> _open(HgAnnouncement announcement) async {
    final controller = context.read<HgAnnouncementController>();
    final handled =
        controller.isAcknowledged(announcement.id) ||
        controller.isSnoozed(announcement.id);
    final decision = await showHgAnnouncementSheet(
      context,
      announcement,
      handled: handled,
    );
    if (decision == HgAnnouncementDecision.today) {
      await controller.snoozeToday(announcement.id);
    } else if (decision == HgAnnouncementDecision.acknowledge) {
      await controller.acknowledge(announcement.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HgAnnouncementController>();
    final announcements = controller.announcements;
    return Scaffold(
      backgroundColor: context.hgSurfaceLow,
      appBar: AppBar(
        backgroundColor: context.hgSurfaceLow,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
        ),
        title: const Text(
          '公告中心',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: '刷新公告',
            onPressed: controller.isRefreshing
                ? null
                : () => unawaited(_refresh()),
            icon: controller.isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded, size: 21),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: HgRefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 34),
          children: [
            const _AnnouncementIntro(),
            if (controller.lastError != null) ...[
              const SizedBox(height: 10),
              _AnnouncementNetworkNotice(message: controller.lastError!),
            ],
            const SizedBox(height: 18),
            if (announcements.isEmpty)
              const _AnnouncementEmpty()
            else
              for (var index = 0; index < announcements.length; index++) ...[
                _AnnouncementCard(
                  announcement: announcements[index],
                  status: _statusFor(controller, announcements[index]),
                  onTap: () => unawaited(_open(announcements[index])),
                ),
                if (index != announcements.length - 1)
                  const SizedBox(height: 12),
              ],
          ],
        ),
      ),
    );
  }

  String _statusFor(
    HgAnnouncementController controller,
    HgAnnouncement announcement,
  ) {
    final now = DateTime.now().toUtc();
    if (!announcement.isActiveAt(now)) return '已结束';
    if (controller.isAcknowledged(announcement.id)) return '已读';
    if (controller.isSnoozed(announcement.id)) return '今日稍后';
    return '未读';
  }
}

class _AnnouncementIntro extends StatelessWidget {
  const _AnnouncementIntro();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      decoration: BoxDecoration(
        color: HgColors.ink,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: HgColors.orange,
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(
              Icons.campaign_rounded,
              color: Colors.white,
              size: 25,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '果幕公告',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '新版本、新项目、活动与维护通知都会在这里发布。',
                  style: TextStyle(
                    color: Color(0xB8FFFFFF),
                    fontSize: 11.5,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AnnouncementNetworkNotice extends StatelessWidget {
  const _AnnouncementNetworkNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: context.hgSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, color: context.hgMuted, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$message，当前显示上次成功获取的公告。',
              style: TextStyle(color: context.hgMuted, fontSize: 10.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({
    required this.announcement,
    required this.status,
    required this.onTap,
  });

  final HgAnnouncement announcement;
  final String status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = status == '未读';
    return Material(
      color: context.hgSurface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(17, 16, 15, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: announcement.isImportant
                          ? HgColors.orange.withValues(alpha: 0.13)
                          : context.hgSurfaceMuted,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      announcement.isImportant
                          ? '重要公告'
                          : _typeLabel(announcement.type),
                      style: TextStyle(
                        color: announcement.isImportant
                            ? HgColors.orange
                            : context.hgMuted,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (unread)
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: HgColors.orange,
                        shape: BoxShape.circle,
                      ),
                    ),
                  const Spacer(),
                  Text(
                    status,
                    style: TextStyle(
                      color: unread ? HgColors.orange : context.hgSubtle,
                      fontSize: 9.5,
                      fontWeight: unread ? FontWeight.w800 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 11),
              Text(
                announcement.title,
                style: TextStyle(
                  color: context.hgOnSurface,
                  fontSize: 18,
                  height: 1.25,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.35,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                announcement.body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.hgMuted,
                  fontSize: 12,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    _dateLabel(announcement.publishedAt.toLocal()),
                    style: TextStyle(color: context.hgSubtle, fontSize: 10),
                  ),
                  const Spacer(),
                  if (announcement.action != null)
                    Text(
                      announcement.action!.label,
                      style: const TextStyle(
                        color: HgColors.orange,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: context.hgSubtle,
                    size: 18,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnnouncementEmpty extends StatelessWidget {
  const _AnnouncementEmpty();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 70),
      child: Column(
        children: [
          Icon(
            Icons.mark_email_read_outlined,
            color: context.hgSubtle,
            size: 42,
          ),
          const SizedBox(height: 12),
          Text(
            '暂时没有公告',
            style: TextStyle(
              color: context.hgOnSurface,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '新版本、新项目与活动通知会出现在这里。',
            style: TextStyle(color: context.hgMuted, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}

String _typeLabel(HgAnnouncementType type) => switch (type) {
  HgAnnouncementType.notice => '系统公告',
  HgAnnouncementType.activity => '活动通知',
  HgAnnouncementType.project => '新项目',
  HgAnnouncementType.maintenance => '维护通知',
};

String _dateLabel(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '${value.year}.$month.$day $hour:$minute';
}
