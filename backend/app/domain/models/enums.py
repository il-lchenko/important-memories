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
    FREE = "free"
    P10 = "p10"
    P25 = "p25"
    P50 = "p50"
    P100 = "p100"
    P150 = "p150"
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
