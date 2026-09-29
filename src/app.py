"""Минимальный HTTP-сервис: /health, /version, /add."""
import os

from flask import Flask, jsonify, request

APP_VERSION = os.environ.get("APP_VERSION", "0.0.0")

app = Flask(__name__)


def add(a: int, b: int) -> int:
    """Сложение двух целых чисел."""
    return a + b


@app.get("/health")
def health():
    return "", 200


@app.get("/version")
def version():
    return jsonify(version=APP_VERSION), 200


@app.get("/add")
def add_endpoint():
    raw_a = request.args.get("a")
    raw_b = request.args.get("b")

    if raw_a is None or raw_b is None:
        return jsonify(error="parameters 'a' and 'b' are required"), 400

    try:
        a = int(raw_a)
        b = int(raw_b)
    except ValueError:
        return jsonify(error="parameters 'a' and 'b' must be integers"), 400

    return jsonify(result=add(a, b)), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)
