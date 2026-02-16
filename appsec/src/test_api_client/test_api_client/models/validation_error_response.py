from __future__ import annotations

from collections.abc import Mapping
from typing import TYPE_CHECKING, Any, TypeVar

from attrs import define as _attrs_define

if TYPE_CHECKING:
    from ..models.validation_error_item import ValidationErrorItem


T = TypeVar("T", bound="ValidationErrorResponse")


@_attrs_define
class ValidationErrorResponse:
    """
    Attributes:
        detail (list[ValidationErrorItem]):
    """

    detail: list[ValidationErrorItem]

    def to_dict(self) -> dict[str, Any]:
        detail = []
        for detail_item_data in self.detail:
            detail_item = detail_item_data.to_dict()
            detail.append(detail_item)

        field_dict: dict[str, Any] = {}

        field_dict.update(
            {
                "detail": detail,
            }
        )

        return field_dict

    @classmethod
    def from_dict(cls: type[T], src_dict: Mapping[str, Any]) -> T:
        from ..models.validation_error_item import ValidationErrorItem

        d = dict(src_dict)
        detail = []
        _detail = d.pop("detail")
        for detail_item_data in _detail:
            detail_item = ValidationErrorItem.from_dict(detail_item_data)

            detail.append(detail_item)

        validation_error_response = cls(
            detail=detail,
        )

        return validation_error_response
