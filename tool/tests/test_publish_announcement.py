import copy
import importlib.util
from datetime import datetime, timezone
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location(
    "publish_announcement",
    Path(__file__).parents[1] / "publish_announcement.py",
)
publish = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publish)

NOW = datetime(2026, 11, 26, 20, 0, tzinfo=timezone.utc)
BASE_FEED = {
    "schema_version": 1,
    "updated_at": "2026-11-26T19:00:00.000Z",
    "announcements": [],
}


class AnnouncementPublisherTests(unittest.TestCase):
    def test_valid_feed(self):
        publish.validate_feed(BASE_FEED)

    def test_new_announcement_is_sorted_and_gets_stable_fields(self):
        feed = copy.deepcopy(BASE_FEED)
        feed["announcements"].append(
            {
                "id": "older",
                "type": "notice",
                "priority": "normal",
                "title": "旧公告",
                "body": "旧内容",
                "published_at": "2026-11-25T00:00:00Z",
                "expires_at": None,
                "action": None,
            }
        )
        updated = publish.upsert_announcement(
            feed,
            announcement_id="new-item",
            announcement_type="project",
            priority="important",
            title="新项目",
            body="新的项目公告",
            published_at="2026-11-26T20:00:00Z",
            action_label="查看详情",
            action_url="https://github.com/DearLicy/dramora",
            now=NOW,
        )
        self.assertEqual([item["id"] for item in updated["announcements"]], ["new-item", "older"])
        self.assertEqual(updated["announcements"][0]["type"], "project")
        self.assertEqual(updated["updated_at"], "2026-11-26T20:00:00.000Z")

    def test_update_by_id_preserves_publish_time(self):
        feed = copy.deepcopy(BASE_FEED)
        created = publish.upsert_announcement(
            feed,
            announcement_id="same-id",
            announcement_type="notice",
            priority="normal",
            title="原标题",
            body="原正文",
            published_at="2026-11-20T00:00:00Z",
            now=NOW,
        )
        updated = publish.upsert_announcement(
            created,
            announcement_id="same-id",
            announcement_type="notice",
            priority="important",
            title="修正标题",
            body="修正正文",
            now=NOW,
        )
        self.assertEqual(len(updated["announcements"]), 1)
        self.assertEqual(updated["announcements"][0]["title"], "修正标题")
        self.assertEqual(
            updated["announcements"][0]["published_at"], "2026-11-20T00:00:00.000Z"
        )

    def test_rejects_insecure_or_partial_action(self):
        with self.assertRaises(publish.AnnouncementValidationError):
            publish.upsert_announcement(
                copy.deepcopy(BASE_FEED),
                announcement_id="bad-link",
                announcement_type="notice",
                priority="normal",
                title="公告",
                body="正文",
                action_label="打开",
                action_url="http://example.com",
                now=NOW,
            )
        with self.assertRaises(publish.AnnouncementValidationError):
            publish.upsert_announcement(
                copy.deepcopy(BASE_FEED),
                announcement_id="partial",
                announcement_type="notice",
                priority="normal",
                title="公告",
                body="正文",
                action_label="打开",
                now=NOW,
            )

    def test_rejects_duplicate_ids_and_invalid_expiry(self):
        feed = copy.deepcopy(BASE_FEED)
        item = {
            "id": "dup",
            "type": "notice",
            "priority": "normal",
            "title": "公告",
            "body": "正文",
            "published_at": "2026-11-26T00:00:00Z",
            "expires_at": "2026-11-25T00:00:00Z",
            "action": None,
        }
        feed["announcements"] = [item, copy.deepcopy(item)]
        with self.assertRaises(publish.AnnouncementValidationError):
            publish.validate_feed(feed)


if __name__ == "__main__":
    unittest.main()
