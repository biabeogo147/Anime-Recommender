import logging
from pathlib import Path

import yaml

logger = logging.getLogger(__name__)


class Pricing:
    """USD per 1M tokens per model, loaded from config/pricing.yaml."""

    def __init__(self, models: dict[str, dict[str, float]]):
        self.models = models
        self._warned: set[str] = set()

    @classmethod
    def load(cls, path: Path) -> "Pricing":
        data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
        return cls(data.get("models", {}))

    def cost_usd(self, model: str, input_tokens: int, output_tokens: int) -> float:
        price = self.models.get(model)
        if price is None:
            if model not in self._warned:
                logger.warning("No pricing for model %s; cost recorded as 0", model)
                self._warned.add(model)
            return 0.0
        return (input_tokens * price["input_per_1m"] + output_tokens * price["output_per_1m"]) / 1_000_000
