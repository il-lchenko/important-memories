"""Entry point that forces SelectorEventLoop on Windows for psycopg compatibility.

uvicorn's stock setup hard-codes WindowsProactorEventLoopPolicy on Windows,
which breaks psycopg. We bypass that by constructing the loop ourselves
and running uvicorn.Server inside it.
"""

import asyncio
import sys

if sys.platform == "win32":
    asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())

import uvicorn


def main() -> None:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
    config = uvicorn.Config(
        "app.main:app",
        host="0.0.0.0",
        port=port,
        log_level="info",
        reload=False,
        loop="none",
    )
    server = uvicorn.Server(config)
    asyncio.run(server.serve())


if __name__ == "__main__":
    main()
