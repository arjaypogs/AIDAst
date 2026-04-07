"""
Bootstrap a default admin user on first startup.

If no users exist in the database, create an `admin` account with either the
password from AIDA_INITIAL_ADMIN_PASSWORD or a randomly generated one. The
generated password is logged once at WARNING level — same pattern as GitLab
and Jenkins.
"""
import os
import secrets

from sqlalchemy.orm import Session

from auth import hash_password
from database import SessionLocal
from models.user import User
from utils.logger import get_logger

logger = get_logger(__name__)

ADMIN_USERNAME = "admin"


def bootstrap_admin() -> None:
    """Create the default admin account if no users exist."""
    db: Session = SessionLocal()
    try:
        if db.query(User).count() > 0:
            return

        env_password = os.getenv("AIDA_INITIAL_ADMIN_PASSWORD")
        password = env_password or secrets.token_urlsafe(16)

        admin = User(
            username=ADMIN_USERNAME,
            email=None,
            hashed_password=hash_password(password),
            is_active=True,
            role="admin",
            must_change_password=True,
        )
        db.add(admin)
        db.commit()

        if not env_password:
            logger.warning("=" * 60)
            logger.warning("INITIAL ADMIN ACCOUNT CREATED")
            logger.warning(f"  username: {ADMIN_USERNAME}")
            logger.warning(f"  password: {password}")
            logger.warning("  You will be asked to change it on first login.")
            logger.warning("=" * 60)
        else:
            logger.warning(
                "Initial admin account created from AIDA_INITIAL_ADMIN_PASSWORD env var"
            )
    finally:
        db.close()
