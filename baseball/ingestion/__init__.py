"""baseball.ingestion — data ingestion workers.

Provides ingesters for all baseball data sources:
- RetrosheetIngester: Retrosheet event files
- StatcastIngester: Statcast/pybaseball pitch telemetry
- MLBAMIngester: MLB StatsAPI data
- FanGraphsIngester: FanGraphs stats and splits
- BRefIngester: Baseball Reference data
- ESPNIngester: ESPN schedule and scores
- OddsIngester: Betting odds data
- LahmanIngester: Lahman database CSV files
"""

from baseball.ingestion.base import BaseIngester, IngestResult
from baseball.ingestion.bref import BRefIngester
from baseball.ingestion.espn import ESPNIngester
from baseball.ingestion.fangraphs import FanGraphsIngester
from baseball.ingestion.lahman import LahmanIngester
from baseball.ingestion.mlbam import MLBAMIngester
from baseball.ingestion.odds import OddsIngester
from baseball.ingestion.retrosheet import RetrosheetIngester
from baseball.ingestion.statcast import StatcastIngester

__all__ = [
    "BaseIngester",
    "IngestResult",
    "RetrosheetIngester",
    "StatcastIngester",
    "MLBAMIngester",
    "FanGraphsIngester",
    "BRefIngester",
    "ESPNIngester",
    "OddsIngester",
    "LahmanIngester",
]
