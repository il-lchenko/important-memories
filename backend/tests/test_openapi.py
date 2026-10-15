from collections import Counter

from app.main import app


def test_openapi_operation_ids_unique_and_security_schemes() -> None:
    schema = app.openapi()
    ids = [
        op["operationId"]
        for path in schema["paths"].values()
        for op in path.values()
        if isinstance(op, dict) and "operationId" in op
    ]
    assert [i for i, c in Counter(ids).items() if c > 1] == []
    schemes = schema["components"]["securitySchemes"]
    assert schemes["HostBearer"]["scheme"] == "bearer"
    assert schemes["GuestToken"]["name"] == "X-Guest-Token"


def test_former_dict_endpoints_have_response_models() -> None:
    schema = app.openapi()
    for path, method in [
        ("/api/v1/events/{event_id}/public-share", "get"),
        ("/api/v1/guest/invites/{token}", "get"),
        ("/api/v1/public/albums/{token}", "get"),
        ("/api/v1/consent/status", "get"),
    ]:
        content = schema["paths"][path][method]["responses"]["200"]["content"]
        assert "$ref" in content["application/json"]["schema"], path
