"""Notes API: one Lambda function behind an API Gateway HTTP API.

GET  /notes   returns up to 50 notes
POST /notes   body {"text": "..."} creates a note

boto3 (the AWS SDK for Python) is already installed in the Lambda runtime,
so there is nothing to package besides this file.
"""

import base64
import json
import os
import uuid
from datetime import datetime, timezone

import boto3

# Created once per container, outside the handler, so warm invocations reuse
# the connection. This is the standard Lambda cold start optimization.
TABLE = boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"])

MAX_TEXT_LENGTH = 500


def respond(status, body):
    return {
        "statusCode": status,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(body),
    }


def parse_body(event):
    raw = event.get("body") or ""
    if event.get("isBase64Encoded"):
        raw = base64.b64decode(raw).decode("utf-8")
    try:
        data = json.loads(raw)
    except (ValueError, TypeError):
        return None
    return data if isinstance(data, dict) else None


def list_notes():
    # Scan reads the whole table, which is fine for a demo and a bad idea at
    # scale. A real design would Query on a key or an index instead.
    items = TABLE.scan(Limit=50).get("Items", [])
    items.sort(key=lambda item: item.get("created_at", ""), reverse=True)
    return respond(200, {"notes": items})


def create_note(event):
    data = parse_body(event)
    text = data.get("text") if data else None
    if not isinstance(text, str) or not text.strip():
        return respond(400, {"error": 'Send JSON like {"text": "hello"}'})
    if len(text) > MAX_TEXT_LENGTH:
        return respond(400, {"error": f"text must be {MAX_TEXT_LENGTH} characters or fewer"})

    note = {
        "id": str(uuid.uuid4()),
        "text": text.strip(),
        "created_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }
    TABLE.put_item(Item=note)
    return respond(201, note)


def lambda_handler(event, context):
    # With payload format 2.0, routeKey looks like "GET /notes".
    route = event.get("routeKey", "")
    print(json.dumps({"route": route, "request_id": context.aws_request_id}))

    if route == "GET /notes":
        return list_notes()
    if route == "POST /notes":
        return create_note(event)
    return respond(404, {"error": f"No route for {route}"})
