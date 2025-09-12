import os
import pytest
import asyncio
from fastapi.testclient import TestClient
from fastapi import status
from server import app, message_queue

# Set up test client
client = TestClient(app)

# Constants and environment
WEBHOOK_TOKEN = os.environ.get("WEBHOOK_TOKEN", "test-token")
INVALID_TOKEN = "invalid-token"
TEST_PAYLOAD = {"msg": "test-message"}

@pytest.fixture(autouse=True)
def clear_queue():
    # Ensure the queue is empty before each test
    while not message_queue.empty():
        message_queue.get_nowait()

@pytest.mark.parametrize("token, expected_status", [
    (INVALID_TOKEN, status.HTTP_401_UNAUTHORIZED),
    (WEBHOOK_TOKEN, status.HTTP_200_OK)
])
def test_webhook_auth(token, expected_status):
    response = client.post(
        "/webhook",
        headers={"x-auth-token": token},
        json=TEST_PAYLOAD
    )
    assert response.status_code == expected_status
    if expected_status == status.HTTP_200_OK:
        assert response.json()["status"] == "queued"
    else:
        assert "error" in response.json()

def test_healthcheck():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}

def test_cors_headers():
    response = client.options("/webhook", headers={"Origin": "http://example.com"})
    # FastAPI CORS middleware should include Access-Control headers
    assert "access-control-allow-origin" in response.headers

def test_websocket_auth_failure():
    with pytest.raises(Exception):
        with client.websocket_connect(f"/ws?token={INVALID_TOKEN}") as websocket:
            websocket.receive_json()

def test_webhook_to_websocket():
    # Send webhook event
    response = client.post(
        "/webhook",
        headers={"x-auth-token": WEBHOOK_TOKEN},
        json=TEST_PAYLOAD
    )
    assert response.status_code == 200
    # Connect websocket and get message
    with client.websocket_connect(f"/ws?token={WEBHOOK_TOKEN}") as websocket:
        data = websocket.receive_json()
        assert data == TEST_PAYLOAD

def test_no_persistence():
    # After event delivery, the queue should be empty
    assert message_queue.empty()

def test_multiple_webhooks_to_websocket():
    # Send multiple events
    payloads = [{"msg": f"event-{i}"} for i in range(3)]
    for payload in payloads:
        response = client.post(
            "/webhook",
            headers={"x-auth-token": WEBHOOK_TOKEN},
            json=payload
        )
        assert response.status_code == 200

    # Connect websocket and receive all messages
    with client.websocket_connect(f"/ws?token={WEBHOOK_TOKEN}") as websocket:
        for payload in payloads:
            data = websocket.receive_json()
            assert data == payload
    # Queue should be empty after consumption
    assert message_queue.empty()

def test_websocket_disconnect():
    # Send event
    client.post(
        "/webhook",
        headers={"x-auth-token": WEBHOOK_TOKEN},
        json=TEST_PAYLOAD
    )
    # Connect and close websocket before consuming
    with client.websocket_connect(f"/ws?token={WEBHOOK_TOKEN}") as websocket:
        websocket.close()
    # The message is consumed even on disconnect
    assert message_queue.empty()