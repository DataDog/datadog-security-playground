from __future__ import annotations

from collections.abc import Mapping
from typing import Any, Literal, TypeVar, cast

from attrs import define as _attrs_define

T = TypeVar("T", bound="SignupResponse")


@_attrs_define
class SignupResponse:
    """
    Attributes:
        message (Literal['User created successfully']):
    """

    message: Literal["User created successfully"]

    def to_dict(self) -> dict[str, Any]:
        message = self.message

        field_dict: dict[str, Any] = {}

        field_dict.update(
            {
                "message": message,
            }
        )

        return field_dict

    @classmethod
    def from_dict(cls: type[T], src_dict: Mapping[str, Any]) -> T:
        d = dict(src_dict)
        message = cast(Literal["User created successfully"], d.pop("message"))
        if message != "User created successfully":
            raise ValueError(f"message must match const 'User created successfully', got '{message}'")

        signup_response = cls(
            message=message,
        )

        return signup_response
