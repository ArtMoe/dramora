#!/usr/bin/env python3
"""Validate and atomically publish announcements for the Guomu/Dramora feed."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import secrets
import sys
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse

SCHEMA_VERSION = 1
MAX_ANNOUNCEMENTS = 50
TYPES = {"notice", "activity", "project", "maintenance"}
PRIORITIES = {"normal", "important"}
ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$")


class AnnouncementValidationError(ValueError):
    pass


def parse_time(value: object, field: str) -> datetime:
    text = str(value or "").strip()
    if not text:
        raise AnnouncementValidationError(f"{field} 不能为空")
    try:
        parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError as error:
        raise AnnouncementValidationError(f"{field} 不是有效的 ISO 时间") from error
    if parsed.tzinfo is None:
        raise AnnouncementValidationError(f"{field} 必须包含时区")
    return parsed.astimezone(timezone.utc)


def iso_time(value: datetime) -> str:
    return value.astimezone(timezone.utc).isoformat(timespec="milliseconds").replace(
        "+00:00", "Z"
    )


def validate_action(value: object) -> None:
    if value is None:
        return
    if not isinstance(value, dict):
        raise AnnouncementValidationError("action 必须是对象或 null")
    label = str(value.get("label") or "").strip()
    url = str(value.get("url") or "").strip()
    parsed = urlparse(url)
    if not label or len(label) > 24:
        raise AnnouncementValidationError("action.label 无效")
    if parsed.scheme != "https" or not parsed.netloc:
        raise AnnouncementValidationError("action.url 必须使用 HTTPS")


def validate_feed(data: object) -> None:
    if not isinstance(data, dict):
        raise AnnouncementValidationError("公告文件必须是 JSON 对象")
    if data.get("schema_version") != SCHEMA_VERSION:
        raise AnnouncementValidationError("schema_version 必须为 1")
    parse_time(data.get("updated_at"), "updated_at")
    announcements = data.get("announcements")
    if not isinstance(announcements, list) or len(announcements) > MAX_ANNOUNCEMENTS:
        raise AnnouncementValidationError("announcements 必须是最多 50 项的数组")

    seen: set[str] = set()
    for index, item in enumerate(announcements):
        prefix = f"announcements[{index}]"
        if not isinstance(item, dict):
            raise AnnouncementValidationError(f"{prefix} 必须是对象")
        announcement_id = str(item.get("id") or "").strip()
        if not ID_RE.fullmatch(announcement_id):
            raise AnnouncementValidationError(f"{prefix}.id 无效")
        if announcement_id in seen:
            raise AnnouncementValidationError(f"公告 ID 重复：{announcement_id}")
        seen.add(announcement_id)
        if item.get("type") not in TYPES:
            raise AnnouncementValidationError(f"{prefix}.type 无效")
        if item.get("priority") not in PRIORITIES:
            raise AnnouncementValidationError(f"{prefix}.priority 无效")
        title = str(item.get("title") or "").strip()
        body = str(item.get("body") or "").strip()
        if not title or len(title) > 120:
            raise AnnouncementValidationError(f"{prefix}.title 无效")
        if not body or len(body) > 8000:
            raise AnnouncementValidationError(f"{prefix}.body 无效")
        published = parse_time(item.get("published_at"), f"{prefix}.published_at")
        expires_raw = item.get("expires_at")
        if expires_raw is not None and str(expires_raw).strip():
            expires = parse_time(expires_raw, f"{prefix}.expires_at")
            if expires <= published:
                raise AnnouncementValidationError(
                    f"{prefix}.expires_at 必须晚于发布时间"
                )
        validate_action(item.get("action"))


def read_feed(path: Path) -> dict:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise AnnouncementValidationError(f"公告文件不存在：{path}") from error
    except json.JSONDecodeError as error:
        raise AnnouncementValidationError("公告文件不是有效 JSON") from error
    validate_feed(data)
    return data


def write_feed_atomic(path: Path, data: dict) -> None:
    validate_feed(data)
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(f".{path.name}.{secrets.token_hex(4)}.tmp")
    try:
        temp.write_text(
            json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        os.replace(temp, path)
    finally:
        if temp.exists():
            temp.unlink()


def generated_id(now: datetime, title: str) -> str:
    digest = hashlib.sha256(f"{title}:{now.isoformat()}".encode()).hexdigest()[:8]
    return f"announcement-{now:%Y%m%d-%H%M%S}-{digest}"


def upsert_announcement(
    feed: dict,
    *,
    announcement_id: str,
    announcement_type: str,
    priority: str,
    title: str,
    body: str,
    published_at: str = "",
    expires_at: str = "",
    action_label: str = "",
    action_url: str = "",
    now: datetime | None = None,
) -> dict:
    validate_feed(feed)
    current = now or datetime.now(timezone.utc)
    clean_id = announcement_id.strip() or generated_id(current, title)
    announcements = [dict(item) for item in feed["announcements"]]
    existing_index = next(
        (index for index, item in enumerate(announcements) if item["id"] == clean_id),
        None,
    )
    existing = announcements[existing_index] if existing_index is not None else None

    published = (
        parse_time(published_at, "published_at")
        if published_at.strip()
        else parse_time(existing["published_at"], "published_at")
        if existing is not None
        else current
    )
    expiry: str | None
    if expires_at.strip():
        expiry = iso_time(parse_time(expires_at, "expires_at"))
    elif existing is not None:
        expiry = existing.get("expires_at")
    else:
        expiry = None

    action = None
    if action_label.strip() or action_url.strip():
        if not action_label.strip() or not action_url.strip():
            raise AnnouncementValidationError("操作按钮名称和链接必须同时填写")
        action = {"label": action_label.strip(), "url": action_url.strip()}

    item = {
        "id": clean_id,
        "type": announcement_type,
        "priority": priority,
        "title": title.strip(),
        "body": body.strip(),
        "published_at": iso_time(published),
        "expires_at": expiry,
        "action": action,
    }
    if existing_index is None:
        announcements.append(item)
    else:
        announcements[existing_index] = item
    announcements.sort(
        key=lambda entry: parse_time(entry["published_at"], "published_at"),
        reverse=True,
    )
    updated = {
        "schema_version": SCHEMA_VERSION,
        "updated_at": iso_time(current),
        "announcements": announcements,
    }
    validate_feed(updated)
    return updated


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)

    validate = commands.add_parser("validate", help="验证公告 JSON")
    validate.add_argument("path", type=Path)

    publish = commands.add_parser("publish", help="新增或按 ID 更新公告")
    publish.add_argument("--path", type=Path, default=Path("assets/data/announcements.json"))
    publish.add_argument("--id", default="")
    publish.add_argument("--type", choices=sorted(TYPES), default="notice")
    publish.add_argument("--priority", choices=sorted(PRIORITIES), default="normal")
    publish.add_argument("--title", required=True)
    publish.add_argument("--body", required=True)
    publish.add_argument("--published-at", default="")
    publish.add_argument("--expires-at", default="")
    publish.add_argument("--action-label", default="")
    publish.add_argument("--action-url", default="")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        feed = read_feed(args.path)
        if args.command == "validate":
            print(f"公告文件有效：{args.path}")
            return 0
        updated = upsert_announcement(
            feed,
            announcement_id=args.id,
            announcement_type=args.type,
            priority=args.priority,
            title=args.title,
            body=args.body,
            published_at=args.published_at,
            expires_at=args.expires_at,
            action_label=args.action_label,
            action_url=args.action_url,
        )
        write_feed_atomic(args.path, updated)
        print(f"公告已发布：{updated['announcements'][0]['id']}")
        return 0
    except AnnouncementValidationError as error:
        print(f"公告校验失败：{error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
