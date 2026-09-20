"""Ручное обезличивание Гостя по запросу через поддержку (privacy v2.2 §11).

Usage:
    # По UUID гостя (самый надёжный способ):
    docker exec -it im-backend uv run python -m scripts.revoke_guest --guest-id <UUID>

    # Список гостей события по short_code (найти нужный UUID):
    docker exec -it im-backend uv run python -m scripts.revoke_guest --list <SHORT_CODE>

Что делает:
- удаляет caption и voice-файлы у всех фреймов Гостя;
- удаляет аватар Гостя из S3;
- обезличивает записи ConsentRecord этого Гостя;
- удаляет Guest → Frame.guest_id → NULL, автор в альбоме отображается как «Гость».

Само фото ОСТАЁТСЯ в альбоме — на основании законных интересов Хоста и
других участников События.
"""
import argparse
import asyncio
from uuid import UUID

from sqlalchemy import select

from app.core.db import SessionLocal
from app.domain.models import Event, Guest
from app.services.guest_service import anonymize_guest


async def list_guests(short_code: str) -> None:
    async with SessionLocal() as session:
        event = (
            await session.execute(
                select(Event).where(Event.short_code == short_code)
            )
        ).scalar_one_or_none()
        if event is None:
            print(f"Событие с кодом {short_code} не найдено")
            return
        guests = list(
            (
                await session.execute(
                    select(Guest).where(Guest.event_id == event.id).order_by(Guest.joined_at)
                )
            ).scalars().all()
        )
        print(f"Событие: {event.title} ({event.id})")
        print(f"Всего гостей: {len(guests)}")
        for g in guests:
            print(f"  {g.id}  {g.name!r:<25} joined={g.joined_at:%Y-%m-%d %H:%M}")


async def revoke(guest_id: UUID) -> None:
    async with SessionLocal() as session:
        result = await anonymize_guest(session, guest_id)
        print("Гость обезличен:")
        for k, v in result.items():
            print(f"  {k}: {v}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--guest-id", type=str, help="UUID гостя для обезличивания")
    parser.add_argument("--list", type=str, help="short_code события — покажет список гостей")
    args = parser.parse_args()

    if args.list:
        asyncio.run(list_guests(args.list))
    elif args.guest_id:
        asyncio.run(revoke(UUID(args.guest_id)))
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
