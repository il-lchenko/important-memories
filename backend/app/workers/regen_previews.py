"""One-shot: regenerate /thumbs/ and /previews/ for all frames.

Reason: worker previously applied the film filter a SECOND time on top of the
client-side pass, doubling shadow tints and blowing contrast on cinestill.
Now filter is client-only; regenerating from /frames/ (single-pass) gives the
correct single-filter previews/thumbs.

Run inside the backend container:
    docker exec im-backend uv run python -m app.workers.regen_previews
"""
import asyncio
import sys

from sqlalchemy import select

from app.core.db import SessionLocal
from app.domain.models import Frame, FrameStatus
from app.workers.thumbnail import make_thumbnail


async def main() -> None:
    async with SessionLocal() as session:
        result = await session.execute(
            select(Frame.id).where(Frame.status == FrameStatus.UPLOADED)
        )
        ids = [str(r[0]) for r in result.all()]

    total = len(ids)
    print(f"Regenerating thumb+preview for {total} frames", flush=True)
    ok = 0
    fail = 0
    for i, fid in enumerate(ids, 1):
        try:
            await make_thumbnail({}, fid)
            ok += 1
            if i % 10 == 0 or i == total:
                print(f"  [{i}/{total}] ok={ok} fail={fail}", flush=True)
        except Exception as exc:  # noqa: BLE001
            fail += 1
            print(f"  [{i}/{total}] {fid} FAIL: {exc}", flush=True)

    print(f"Done. ok={ok} fail={fail}", flush=True)
    if fail:
        sys.exit(1)


if __name__ == "__main__":
    asyncio.run(main())
