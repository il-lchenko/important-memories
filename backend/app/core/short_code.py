from secrets import choice

_ALPHABET = "abcdefghijkmnpqrstuvwxyz23456789"


def generate(length: int = 8) -> str:
    return "".join(choice(_ALPHABET) for _ in range(length))
