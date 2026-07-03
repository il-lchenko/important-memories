from enum import StrEnum


class EventType(StrEnum):
    WEDDING = "wedding"
    BIRTHDAY = "birthday"
    CORPORATE = "corporate"
    PARTY = "party"
    GRADUATION = "graduation"
    TRAVEL = "travel"
    VACATION = "vacation"
    CONCERT = "concert"
    OTHER = "other"


class EventStatus(StrEnum):
    DRAFT = "draft"
    ACTIVE = "active"
    COMPLETED = "completed"
    CANCELLED = "cancelled"


class RevealMode(StrEnum):
    INSTANT = "instant"
    DELAYED = "delayed"


class Plan(StrEnum):
    # Business plan v3.2 — guest-count pricing grid (analysis/business-plan/index.html §09).
    # Number = max guests included in this tier.
    FREE = "free"    # 5 guests, 14d
    P10 = "p10"      # 10 guests, 249₽, 30d
    P25 = "p25"      # 25, 449₽, 60d
    P50 = "p50"      # 50, 1290₽, 90d ⭐ base
    P75 = "p75"      # 75, 1990₽, 90d
    P100 = "p100"    # 100, 2990₽, 120d ⭐
    P150 = "p150"   # 150, 4490₽, 150d
    P175 = "p175"   # 175, 5490₽, 180d ⭐
    P200 = "p200"   # 200, 6290₽, 180d
    P250 = "p250"   # 250, 7690₽, 240d ⭐
    CUSTOM = "custom"  # 250+ — цена по формуле 7690 + (N-250)*30, срок 240d
    # Deprecated (kept for migration compat — treat as CUSTOM):
    UNLIMITED = "unlimited"


class LutPreset(StrEnum):
    ORIGINAL = "original"
    PORTRA400 = "portra400"
    FUJI400H = "fuji400h"
    CINESTILL = "cinestill"
    ILFORD = "ilford"


class FrameStatus(StrEnum):
    PENDING = "pending"
    UPLOADED = "uploaded"
    DELETED = "deleted"


class PaymentStatus(StrEnum):
    PENDING = "pending"
    SUCCEEDED = "succeeded"
    CANCELLED = "cancelled"
    REFUNDED = "refunded"


class Platform(StrEnum):
    IOS = "ios"
    ANDROID = "android"
    WEB = "web"
    HUAWEI = "huawei"


class ReportCategory(StrEnum):
    NUDITY = "nudity"
    VIOLENCE = "violence"
    SPAM = "spam"
    OTHER = "other"


class ReportStatus(StrEnum):
    OPEN = "open"
    RESOLVED = "resolved"
    DISMISSED = "dismissed"


class PhotoFormat(StrEnum):
    PORTRAIT_34 = "portrait_34"
    LANDSCAPE_43 = "landscape_43"
