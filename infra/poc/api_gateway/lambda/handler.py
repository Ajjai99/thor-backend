import json


# GET /status/<code> answers with <code>, so any 2xx/4xx/5xx can be produced on demand.
# Anything else answers 200.
def handler(event, context):
    parts = event.get("rawPath", "/").strip("/").split("/")
    status = 200
    if len(parts) == 2 and parts[0] == "status" and parts[1].isdigit():
        status = int(parts[1])

    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"status": status, "path": event.get("rawPath")}),
    }
