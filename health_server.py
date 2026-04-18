from flask import jsonify

from app import app as flask_app
from db import init_db


# Ensure DB schema is ready when running via Gunicorn (`health_server:app`).
init_db()


@flask_app.get("/health")
@flask_app.get("/healthz")
def health_check():
    return jsonify({"status": "ok"}), 200


app = flask_app


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
