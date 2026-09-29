"""Проверки эндпоинта /add и вспомогательных маршрутов."""
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from app import app as flask_app  # noqa: E402


@pytest.fixture
def client():
    flask_app.config.update(TESTING=True)
    with flask_app.test_client() as test_client:
        yield test_client


def test_add_positive(client):
    """2 + 3 = 5"""
    response = client.get("/add?a=2&b=3")
    assert response.status_code == 200
    assert response.get_json() == {"result": 5}


def test_add_negative(client):
    """-2 + 1 = -1"""
    response = client.get("/add?a=-2&b=1")
    assert response.status_code == 200
    assert response.get_json() == {"result": -1}


def test_add_missing_parameter(client):
    """Отсутствующий параметр даёт 400."""
    assert client.get("/add?a=2").status_code == 400
    assert client.get("/add?b=3").status_code == 400
    assert client.get("/add").status_code == 400


def test_add_non_numeric_parameter(client):
    """Нечисловой параметр даёт 400."""
    assert client.get("/add?a=x&b=3").status_code == 400
    assert client.get("/add?a=2&b=y").status_code == 400
    assert client.get("/add?a=1.5&b=2").status_code == 400


def test_health(client):
    response = client.get("/health")
    assert response.status_code == 200


def test_version(client):
    response = client.get("/version")
    assert response.status_code == 200
    assert "version" in response.get_json()
