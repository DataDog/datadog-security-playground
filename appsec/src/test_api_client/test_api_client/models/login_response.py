from __future__ import annotations

from collections.abc import Mapping
from typing import Any, Literal, TypeVar, cast

from attrs import define as _attrs_define

T = TypeVar("T", bound="LoginResponse")


@_attrs_define
class LoginResponse:
    """
    Attributes:
        message (Literal['Login successful']):
        access_token (str):
        token_type (Literal['bearer']):
    """

    message: Literal["Login successful"]
    access_token: str
    token_type: Literal["bearer"]

    def to_dict(self) -> dict[str, Any]:
        message = self.message

        access_token = self.access_token

        token_type = self.token_type

        field_dict: dict[str, Any] = {}

        field_dict.update(
            {
                "message": message,
                "access_token": access_token,
                "token_type": token_type,
            }
        )

        return field_dict

    @classmethod
    def from_dict(cls: type[T], src_dict: Mapping[str, Any]) -> T:
        d = dict(src_dict)
        message = cast(Literal["Login successful"], d.pop("message"))
        if message != "Login successful":
            raise ValueError(f"message must match const 'Login successful', got '{message}'")

        access_token = d.pop("access_token")

        token_type = cast(Literal["bearer"], d.pop("token_type"))
        if token_type != "bearer":
            raise ValueError(f"token_type must match const 'bearer', got '{token_type}'")

        login_response = cls(
            message=message,
            access_token=access_token,
            token_type=token_type,
        )

        return login_response
