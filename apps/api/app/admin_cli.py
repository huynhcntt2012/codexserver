"""Creates or resets an admin account from the server shell; there is no default admin.

    docker compose exec api python -m app.admin_cli create <username> --role owner
The password is read from the ADMIN_PASSWORD environment variable or prompted.
"""

import argparse
import getpass
import os
import sys

from sqlalchemy import select


def main() -> int:
    # app.main wires every router; importing it first avoids a partial admin_auth import.
    import app.main  # noqa: F401
    from app.admin_auth import AdminUser, audit, create_admin
    from app.main import SessionLocal, password_hash

    parser = argparse.ArgumentParser(prog="python -m app.admin_cli")
    parser.add_argument("command", choices=["create", "reset-password", "import-icons"])
    parser.add_argument("username", help="admin name, or the asset folder for import-icons")
    parser.add_argument("--role", choices=["owner", "operator", "viewer"], default="owner")
    args = parser.parse_args()
    if args.command == "import-icons":
        return import_icons(args.username)
    password = os.environ.get("ADMIN_PASSWORD") or getpass.getpass("Admin password: ")
    if len(password) < 12:
        print("Password needs at least 12 characters.", file=sys.stderr)
        return 1
    with SessionLocal() as db:
        admin = db.scalar(select(AdminUser).where(AdminUser.username == args.username.lower()))
        if args.command == "create":
            if admin:
                print("Admin already exists.", file=sys.stderr)
                return 1
            admin = create_admin(db, args.username, password, args.role)
            audit(db, None, "admin.created_cli", "admin", admin.id, role=args.role)
        else:
            if not admin:
                print("Admin not found.", file=sys.stderr)
                return 1
            admin.password = password_hash.hash(password)
            audit(db, None, "admin.password_reset_cli", "admin", admin.id)
        db.commit()
    print(f"OK: {args.command} {args.username.lower()}")
    return 0


def import_icons(folder: str) -> int:
    """Stores each catalog item's PNG (icon path relative to folder) as a server asset."""
    import app.main  # noqa: F401
    from app.admin_api import ItemCatalog
    from app.admin_auth import audit
    from app.economy import store_asset
    from app.main import SessionLocal

    done = 0
    with SessionLocal() as db:
        for item in db.scalars(select(ItemCatalog).where(ItemCatalog.icon.is_not(None))):
            path = os.path.join(folder, item.icon)
            if not os.path.isfile(path):
                print(f"skip {item.id}: {path} missing", file=sys.stderr)
                continue
            with open(path, "rb") as handle:
                asset = store_asset(db, handle.read())
            if item.icon_sha256 != asset.sha256:
                item.icon_sha256 = asset.sha256
                audit(db, None, "item.icon", "item", item.id, after=asset.sha256)
                done += 1
        db.commit()
    print(f"OK: {done} icons imported")
    return 0


if __name__ == "__main__":
    sys.exit(main())
