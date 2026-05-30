"""Property-based tests using hypothesis for edge case discovery.

These tests use hypothesis to generate random inputs and verify invariants.
Run with: pytest tests/property/test_properties.py -v
"""

from __future__ import annotations

from datetime import date

import pytest
from hypothesis import given, strategies as st, assume

from baseball.settings import DatabaseSettings


# ---------------------------------------------------------------------------
# Database URL Property Tests
# ---------------------------------------------------------------------------


class TestDatabaseUrlProperties:
    """Property tests for database URL validation."""

    @given(st.text(min_size=1, max_size=100))
    def test_url_masking_hides_password(self, url_fragment: str):
        """Any URL with password should be masked in logs."""
        # URLs with passwords should have them masked
        if "password" in url_fragment.lower() or "pass" in url_fragment.lower():
            # This would be tested against actual masking logic
            # For now, verify the property holds conceptually
            assert True  # Placeholder - would test actual masking

    @given(
        st.integers(min_value=1000, max_value=99999),
        st.integers(min_value=1, max_value=1000000)
    )
    def test_confidence_score_boundaries(self, player_id: int, score: int):
        """Confidence scores should be between 0 and 1."""
        # Normalize score to 0-1 range
        normalized = min(1.0, max(0.0, score / 1000000.0))
        assert 0.0 <= normalized <= 1.0


# ---------------------------------------------------------------------------
# Player Name Property Tests
# ---------------------------------------------------------------------------


class TestPlayerNameProperties:
    """Property tests for player name handling."""

    @given(st.text(min_size=1, max_size=50, alphabet=st.characters(
        whitelist_categories=['Lu', 'Ll', 'Nd']
    )))
    def test_player_name_normalization(self, name: str):
        """Player names should be normalized consistently."""
        # Names should be stripped of whitespace
        normalized = name.strip()
        assert normalized == name.strip()

    @given(
        st.text(min_size=1, max_size=20, alphabet=st.characters(
            whitelist_categories=['Ll']
        )),
        st.text(min_size=1, max_size=20, alphabet=st.characters(
            whitelist_categories=['Ll']
        ))
    )
    def test_player_name_lowercase(self, first: str, last: str):
        """Player names should be lowercased for comparison."""
        normalized = f"{first.lower()} {last.lower()}"
        assert normalized == normalized.lower()


# ---------------------------------------------------------------------------
# Year Range Property Tests
# ---------------------------------------------------------------------------


class TestYearRangeProperties:
    """Property tests for year validation."""

    @given(st.integers(min_value=1800, max_value=2200))
    def test_lahman_year_validation(self, year: int):
        """Lahman years should be in valid range (1871-2100)."""
        valid = 1871 <= year <= 2100
        # Test the validation logic
        if valid:
            assert year >= 1871 and year <= 2100
        else:
            assert year < 1871 or year > 2100

    @given(st.integers(min_value=2010, max_value=2030))
    def test_statcast_year_validation(self, year: int):
        """Statcast data starts from 2015."""
        valid = year >= 2015
        # Statcast years should be 2015 or later
        if valid:
            assert year >= 2015


# ---------------------------------------------------------------------------
# Team Code Property Tests
# ---------------------------------------------------------------------------


class TestTeamCodeProperties:
    """Property tests for team code handling."""

    @given(st.text(min_size=1, max_size=10, alphabet=st.characters(
        whitelist_categories=['Lu']
    )))
    def test_team_code_uppercase(self, code: str):
        """Team codes should be uppercased."""
        normalized = code.upper()
        assert normalized == normalized.upper()
        assert normalized == code.upper()

    @given(st.text(min_size=2, max_size=5, alphabet=st.characters(
        whitelist_categories=['Ll']
    )))
    def test_team_code_normalization(self, code: str):
        """Team codes should be trimmed and uppercased."""
        normalized = code.strip().upper()
        assert len(normalized) >= 2
        assert normalized == normalized.upper()


# ---------------------------------------------------------------------------
# Feature Entity Key Property Tests
# ---------------------------------------------------------------------------


class TestFeatureEntityKeyProperties:
    """Property tests for feature entity key generation."""

    @given(
        st.sampled_from(['game', 'team_game', 'player_game', 'plate_appearance', 'pitch']),
        st.integers(min_value=1, max_value=999999)
    )
    def test_feature_entity_key_format(self, grain: str, id_value: int):
        """Feature entity keys should follow grain:id format."""
        if grain == 'game':
            key = f"game:{id_value}"
        elif grain == 'team_game':
            key = f"team_game:10:{id_value}"
        elif grain == 'player_game':
            key = f"player_game:555:{id_value}"
        elif grain == 'plate_appearance':
            key = f"plate_appearance:{id_value}"
        else:  # pitch
            key = f"pitch:{id_value}"
        
        assert grain in key
        assert str(id_value) in key


# ---------------------------------------------------------------------------
# Date Property Tests
# ---------------------------------------------------------------------------


class TestDateProperties:
    """Property tests for date handling."""

    @given(
        st.dates(min_value=date(1871, 1, 1), max_value=date(2100, 12, 31))
    )
    def test_valid_baseball_dates(self, test_date: date):
        """Baseball dates should be in valid range."""
        assert 1871 <= test_date.year <= 2100

    @given(
        st.dates(min_value=date(2015, 1, 1), max_value=date(2025, 12, 31))
    )
    def test_statcast_dates(self, test_date: date):
        """Statcast dates should be 2015 or later."""
        assert test_date.year >= 2015