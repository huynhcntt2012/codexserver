"""Creates the Robot Bom Dây Cót boss event from the API's robot template (docs/BOSS.md).

Uses only the admin API: login -> GET /admin/v1/events/template?kind=robot ->
validate -> create (draft) -> publish (only with --publish). Standard library only.

    python3 scripts/create-robot-event.py --user <admin>
    python3 scripts/create-robot-event.py --user <admin> --open-now --publish

The password is read from ADMIN_PASSWORD or prompted; an MFA code is asked when needed.
Without --publish the event stays a draft; publish it later from the admin portal or:
    curl -X POST <api>/admin/v1/events/<id>/publish -H "Authorization: Bearer <token>"
"""

import argparse
import getpass
import json
import os
import sys
import urllib.error
import urllib.request
from datetime import UTC, datetime, timedelta


def call(api: str, method: str, path: str, token: str = "", body=None):
    request = urllib.request.Request(api.rstrip("/") + path, method=method)
    request.add_header("Content-Type", "application/json")
    if token:
        request.add_header("Authorization", "Bearer " + token)
    data = json.dumps(body).encode() if body is not None else None
    try:
        with urllib.request.urlopen(request, data, timeout=30) as response:
            return response.status, json.loads(response.read() or b"null")
    except urllib.error.HTTPError as error:
        raw = error.read()
        try:
            return error.code, json.loads(raw)
        except ValueError:
            return error.code, raw.decode(errors="replace")


def login(api: str, user: str) -> str:
    password = os.environ.get("ADMIN_PASSWORD") or getpass.getpass(f"Mật khẩu admin {user}: ")
    body = {"username": user, "password": password}
    status, data = call(api, "POST", "/admin/v1/auth/login", body=body)
    if status == 401 and "MFA" in str(data):
        body["otp"] = input("Mã MFA (6 số): ").strip()
        status, data = call(api, "POST", "/admin/v1/auth/login", body=body)
    if status != 200:
        sys.exit(f"Đăng nhập thất bại ({status}): {data}")
    return data["access_token"]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--api", default="http://127.0.0.1:8000", help="API URL")
    parser.add_argument("--user", required=True, help="admin username (owner / operator)")
    parser.add_argument("--days", type=int, default=7, help="event length in days")
    parser.add_argument(
        "--open-now",
        action="store_true",
        help="playable all day (no 19:00-22:00 sessions), starting now",
    )
    parser.add_argument("--map", help="map id (template: harbor)")
    parser.add_argument("--min-players", type=int, help="template: 1 (solo allowed)")
    parser.add_argument("--publish", action="store_true", help="publish after creating")
    args = parser.parse_args()

    token = login(args.api, args.user)
    status, event = call(args.api, "GET", "/admin/v1/events/template?kind=robot", token)
    if status != 200:
        sys.exit(f"Không lấy được mẫu Robot ({status}): {event}. API đã là bản mới chưa?")
    boss = event["config"]["boss"]
    if args.open_now:
        start = datetime.now(UTC) - timedelta(minutes=1)
        event["start_at"] = start.isoformat()
        boss["sessions"] = []
    else:
        start = datetime.fromisoformat(event["start_at"])
    event["end_at"] = (start + timedelta(days=args.days)).isoformat()
    event["claim_end_at"] = (start + timedelta(days=args.days + 3)).isoformat()
    if args.map:
        boss["map_id"] = args.map
    if args.min_players:
        boss["min_players"] = args.min_players

    status, check = call(args.api, "POST", "/admin/v1/events/validate", token, event)
    for warning in check.get("warnings", []) if isinstance(check, dict) else []:
        print("Cảnh báo:", warning)
    if status != 200 or not check.get("ok"):
        errors = check.get("errors", check) if isinstance(check, dict) else check
        sys.exit(f"Cấu hình chưa hợp lệ ({status}): {errors}")

    status, created = call(args.api, "POST", "/admin/v1/events", token, event)
    if status != 201:
        sys.exit(f"Tạo sự kiện thất bại ({status}): {created}")
    event_id = created["id"]
    print(f"Đã tạo bản nháp: {created['name']} ({event_id})")
    print(
        f"  Boss {boss['display_name']}, bản đồ {boss['map_id']}, {boss['min_players']}-"
        f"{boss['max_players']} người, {created['start_at']} -> {created['end_at']}"
    )
    if not args.publish:
        print("Chưa phát hành. Chạy lại với --publish hoặc phát hành trong admin.")
        return 0
    status, published = call(args.api, "POST", f"/admin/v1/events/{event_id}/publish", token)
    if status != 200:
        sys.exit(f"Phát hành thất bại ({status}): {published}")
    print(f"Đã phát hành: trạng thái {published['status']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
