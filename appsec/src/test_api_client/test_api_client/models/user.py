from __future__ import annotations

from collections.abc import Mapping
from typing import Any, TypeVar
from uuid import UUID

from attrs import define as _attrs_define

T = TypeVar("T", bound="User")


@_attrs_define
class User:
    """
    Attributes:
        user_id (UUID):
        username (str):
        email (str):
        phone (str):
        us_ssn (str):
    """

    user_id: UUID
    username: str
    email: str
    phone: str
    us_ssn: str

    def to_dict(self) -> dict[str, Any]:
        user_id = str(self.user_id)

        username = self.username

        email = self.email

        phone = self.phone

        us_ssn = self.us_ssn

        field_dict: dict[str, Any] = {}

        field_dict.update(
            {
                "user_id": user_id,
                "username": username,
                "email": email,
                "phone": phone,
                "us_ssn": us_ssn,
            }
        )

        return field_dict

    @classmethod
    def from_dict(cls: type[T], src_dict: Mapping[str, Any]) -> T:
        d = dict(src_dict)
        user_id = UUID(d.pop("user_id"))

        username = d.pop("username")

        email = d.pop("email")

        phone = d.pop("phone")

        us_ssn = d.pop("us_ssn")

        user = cls(
            user_id=user_id,
            username=username,
            email=email,
            phone=phone,
            us_ssn=us_ssn,
        )

        return user
