from __future__ import annotations

from collections.abc import Mapping
from typing import Any, TypeVar

from attrs import define as _attrs_define

from ..models.api_1_sensitive_by_id_response_username import Api1SensitiveByIdResponseUsername

T = TypeVar("T", bound="Api1SensitiveByIdResponse")


@_attrs_define
class Api1SensitiveByIdResponse:
    """
    Attributes:
        requested_user_id (int):
        username (Api1SensitiveByIdResponseUsername):
        email (str):
        phone (str):
        us_ssn (str):
    """

    requested_user_id: int
    username: Api1SensitiveByIdResponseUsername
    email: str
    phone: str
    us_ssn: str

    def to_dict(self) -> dict[str, Any]:
        requested_user_id = self.requested_user_id

        username = self.username.value

        email = self.email

        phone = self.phone

        us_ssn = self.us_ssn

        field_dict: dict[str, Any] = {}

        field_dict.update(
            {
                "requested_user_id": requested_user_id,
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
        requested_user_id = d.pop("requested_user_id")

        username = Api1SensitiveByIdResponseUsername(d.pop("username"))

        email = d.pop("email")

        phone = d.pop("phone")

        us_ssn = d.pop("us_ssn")

        api_1_sensitive_by_id_response = cls(
            requested_user_id=requested_user_id,
            username=username,
            email=email,
            phone=phone,
            us_ssn=us_ssn,
        )

        return api_1_sensitive_by_id_response
