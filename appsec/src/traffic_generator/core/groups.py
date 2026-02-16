from .model import ScenarioGroup
from .registry import register_group
from .scenarios.rasp_detection import RaspLfiScenario, RaspShiScenario, RaspSsrfScenario
from .scenarios.threat_detection import (
    HealthCommandInjectionThreatScenario,
    HealthLfiThreatScenario,
    HealthSqlInjectionThreatScenario,
    HealthXssThreatScenario,
)


@register_group
class ThreatDetectionScenarioGroup(ScenarioGroup):
    """Ingress-only probes that should emit WAF threat-detection signals."""

    name = "ThreatDetection"
    display_name = "Threat Detection"
    scenarios = (
        HealthSqlInjectionThreatScenario,
        HealthXssThreatScenario,
        HealthCommandInjectionThreatScenario,
        HealthLfiThreatScenario,
    )


@register_group
class RaspDetectionScenarioGroup(ScenarioGroup):
    """Exploit Prevention scenarios.

    Simulate traffic that exploits real vulnerabilities that can be detected using
    App and API Protection RASP capabilities.
    """

    name = "RaspDetection"
    display_name = "RASP Detection"
    scenarios = (
        RaspSsrfScenario,
        RaspShiScenario,
        RaspLfiScenario,
    )
