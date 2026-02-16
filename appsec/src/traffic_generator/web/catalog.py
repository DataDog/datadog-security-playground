from dataclasses import dataclass
from typing import TypedDict

from traffic_generator.core import registry
from traffic_generator.core.model import Scenario, step_metadata


class CatalogStepPayload(TypedDict):
    id: str
    display_name: str
    description: str


class CatalogScenarioPayload(TypedDict):
    name: str
    display_name: str
    description: str
    steps: list[CatalogStepPayload]


class CatalogGroupPayload(TypedDict):
    name: str
    display_name: str
    description: str
    scenarios: list[CatalogScenarioPayload]


class CatalogPayload(TypedDict):
    global_scenarios: list[CatalogScenarioPayload]
    groups: list[CatalogGroupPayload]


@dataclass(slots=True, frozen=True)
class CatalogStep:
    id: str
    display_name: str
    description: str

    def as_payload(self) -> CatalogStepPayload:
        return {
            "id": self.id,
            "display_name": self.display_name,
            "description": self.description,
        }


@dataclass(slots=True, frozen=True)
class CatalogScenario:
    name: str
    display_name: str
    description: str
    steps: tuple[CatalogStep, ...]

    def as_payload(self) -> CatalogScenarioPayload:
        return {
            "name": self.name,
            "display_name": self.display_name,
            "description": self.description,
            "steps": [step.as_payload() for step in self.steps],
        }


@dataclass(slots=True, frozen=True)
class CatalogGroup:
    name: str
    display_name: str
    description: str
    scenarios: tuple[CatalogScenario, ...]

    def as_payload(self) -> CatalogGroupPayload:
        return {
            "name": self.name,
            "display_name": self.display_name,
            "description": self.description,
            "scenarios": [scenario.as_payload() for scenario in self.scenarios],
        }


@dataclass(slots=True, frozen=True)
class Catalog:
    global_scenarios: tuple[CatalogScenario, ...]
    groups: tuple[CatalogGroup, ...]

    def as_payload(self) -> CatalogPayload:
        return {
            "global_scenarios": [
                scenario.as_payload() for scenario in self.global_scenarios
            ],
            "groups": [group.as_payload() for group in self.groups],
        }


def _build_scenario_entry(scenario_class: type[Scenario]) -> CatalogScenario:
    scenario = scenario_class()
    steps = tuple(
        CatalogStep(
            id=metadata.id,
            display_name=metadata.display_name,
            description=metadata.description,
        )
        for metadata in (step_metadata(step) for step in scenario.steps())
    )
    return CatalogScenario(
        name=scenario_class.scenario_name(),
        display_name=scenario_class.scenario_display_name(),
        description=scenario_class.scenario_description(),
        steps=steps,
    )


def build_catalog() -> Catalog:
    registry.load_scenarios()
    all_groups = registry.all_groups()
    grouped_scenarios = {
        scenario_class
        for group in all_groups
        for scenario_class in group.scenarios
    }

    global_scenarios = tuple(
        _build_scenario_entry(scenario_class)
        for scenario_class in registry.all_scenarios()
        if scenario_class not in grouped_scenarios
    )
    groups = tuple(
        CatalogGroup(
            name=group.group_name(),
            display_name=group.group_display_name(),
            description=group.group_description(),
            scenarios=tuple(
                _build_scenario_entry(scenario_class)
                for scenario_class in registry.by_group(group.group_name())
            ),
        )
        for group in all_groups
    )
    return Catalog(global_scenarios=global_scenarios, groups=groups)


def build_catalog_payload() -> CatalogPayload:
    return build_catalog().as_payload()
