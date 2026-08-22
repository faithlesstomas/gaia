#!/usr/bin/env python3
"""One-request HTTP-over-UDS NCSI server used by the Guile transport test."""

from __future__ import annotations

import json
import os
import socket
import sys
from pathlib import Path


def event_stream(request_id: str) -> bytes:
    observation = {
        "schema-version": "gcas.ncsi.v1",
        "request-id": request_id,
        "forward-pass-id": "forward-1",
        "model-id": "fixture-model",
        "model-revision": "revision",
        "tokenizer-revision": "tokenizer",
        "lens-id": "fixture-lens",
        "lens-revision": "lens-revision",
        "layer": 1,
        "position": 0,
        "concepts": [{"token-id": 7, "display-text": "hello", "score": 0.9}],
        "readout-method": "jlens-sparse",
        "parameters": {"top-k": 1},
        "reconstruction-error": 0.0,
        "timestamp": 3.0,
    }
    events = [
        {
            "schema-version": "gcas.ncsi.v1",
            "event-type": "GenerationStarted",
            "request-id": request_id,
            "timestamp": 1.0,
            "payload": {"model-id": "fixture-model"},
        },
        {
            "schema-version": "gcas.ncsi.v1",
            "event-type": "TokenDelta",
            "request-id": request_id,
            "timestamp": 2.0,
            "payload": {"token-id": 7, "token-text": "hello"},
        },
        {
            "schema-version": "gcas.ncsi.v1",
            "event-type": "NeuralStateObserved",
            "request-id": request_id,
            "timestamp": 3.0,
            "payload": observation,
        },
        {
            "schema-version": "gcas.ncsi.v1",
            "event-type": "GenerationCompleted",
            "request-id": request_id,
            "timestamp": 4.0,
            "payload": {"final-text": "hello", "token-count": 1},
        },
    ]
    return ("\n".join(json.dumps(event, separators=(",", ":")) for event in events) + "\n").encode()


def read_request(connection: socket.socket) -> None:
    data = b""
    while b"\r\n\r\n" not in data:
        block = connection.recv(4096)
        if not block:
            return
        data += block
    headers, body = data.split(b"\r\n\r\n", 1)
    content_length = 0
    for line in headers.split(b"\r\n"):
        if line.lower().startswith(b"content-length:"):
            content_length = int(line.split(b":", 1)[1].strip())
    while len(body) < content_length:
        body += connection.recv(4096)


def main() -> None:
    socket_path = Path(sys.argv[1])
    request_id = sys.argv[2]
    status = int(sys.argv[3])
    socket_path.unlink(missing_ok=True)
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        server.bind(os.fspath(socket_path))
        server.listen(1)
        print("READY", flush=True)
        connection, _ = server.accept()
        with connection:
            read_request(connection)
            if status == 200:
                body = event_stream(request_id)
                reason = "OK"
                content_type = "application/x-ndjson"
            else:
                body = b'{"error-code":"INTERNAL_ERROR"}'
                reason = "Internal Server Error"
                content_type = "application/json"
            response = (
                f"HTTP/1.1 {status} {reason}\r\n"
                f"Content-Type: {content_type}\r\n"
                f"Content-Length: {len(body)}\r\n"
                "Connection: close\r\n\r\n"
            ).encode() + body
            connection.sendall(response)
    finally:
        server.close()
        socket_path.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
