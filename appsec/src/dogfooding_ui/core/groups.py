from .model import ScenarioGroup
from .registry import register_group
from .scenarios.api1_authenticated_predictable_id import (
    Api1AuthenticatedPredictableIdScenario,
)
from .scenarios.api1_jwt_without_audience import Api1JwtWithoutAudienceScenario
from .scenarios.seed_catalog import SeedCatalogScenario


@register_group
class Api1ScenarioGroup(ScenarioGroup):
    """Scenarios for OWASP API1:2023 supported findings."""

    name = "API1:2023"
    display_name = "API1:2023 Broken Object Level Authorization"
    scenarios = (
        Api1JwtWithoutAudienceScenario,
        Api1AuthenticatedPredictableIdScenario,
    )


@register_group
class DefaultScenarioGroup(ScenarioGroup):
    """Scenarios that seed endpoint telemetry for product exploration."""

    name = "Commons"
    display_name = "Catalog Seeding Scenarios"
    scenarios = (SeedCatalogScenario,)
