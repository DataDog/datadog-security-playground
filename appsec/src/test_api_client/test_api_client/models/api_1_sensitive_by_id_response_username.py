from enum import Enum


class Api1SensitiveByIdResponseUsername(str, Enum):
    ALICE = "alice"
    BOB = "bob"

    def __str__(self) -> str:
        return str(self.value)
