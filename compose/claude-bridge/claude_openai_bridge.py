import asyncio
import json
import os
import subprocess
import time
import uuid
from typing import Any

from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.responses import StreamingResponse

app = FastAPI(title="Local Claude OpenAI Bridge")

BRIDGE_KEY = os.getenv("BRIDGE_KEY", "local-claude-key")
CLAUDE_TIMEOUT = int(os.getenv("CLAUDE_TIMEOUT", "300"))

# Claude Code invocations are relatively heavy.
# Start with one concurrent request.
semaphore = asyncio.Semaphore(
    int(os.getenv("CLAUDE_CONCURRENCY", "1"))
)


def normalize_content(content: Any) -> str:
    if isinstance(content, str):
        return content

    if isinstance(content, list):
        parts: list[str] = []

        for item in content:
            if not isinstance(item, dict):
                continue

            if item.get("type") == "text":
                parts.append(str(item.get("text", "")))
            else:
                parts.append(
                    f"[Unsupported content type: {item.get('type', 'unknown')}]"
                )

        return "\n".join(parts)

    return str(content)


def prepare_conversation(
    messages: list[dict[str, Any]],
) -> tuple[str, str]:
    system_parts: list[str] = []
    transcript: list[str] = []

    for message in messages:
        role = str(message.get("role", "user")).lower()
        content = normalize_content(message.get("content", ""))

        if role == "system":
            system_parts.append(content)
        else:
            transcript.append(f"<{role}>\n{content}\n</{role}>")

    system_prompt = "\n\n".join(system_parts).strip()

    if not system_prompt:
        system_prompt = (
            "You are a helpful assistant. Respond to the final user "
            "message while respecting the preceding conversation."
        )

    prompt = (
        "Here is the conversation transcript:\n\n"
        + "\n\n".join(transcript)
        + "\n\nRespond as the assistant to the final message."
    )

    return system_prompt, prompt


def map_model(requested: str) -> str:
    requested = requested.lower()

    if "opus" in requested:
        return "opus"
    if "haiku" in requested:
        return "haiku"
    if "fable" in requested:
        return "fable"

    return "sonnet"


def invoke_claude(
    messages: list[dict[str, Any]],
    requested_model: str,
) -> str:
    system_prompt, prompt = prepare_conversation(messages)
    claude_model = map_model(requested_model)

    command = [
        "claude",
        "-p",
        "--output-format",
        "json",
        "--no-session-persistence",
        "--model",
        claude_model,
        # Disable Claude Code's local computer tools.
        "--tools",
        "",
        # Also disable MCP tools.
        "--disallowedTools",
        "mcp__*",
        "--system-prompt",
        system_prompt,
        prompt,
    ]

    try:
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=CLAUDE_TIMEOUT,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError("Claude Code timed out") from exc
    except FileNotFoundError as exc:
        raise RuntimeError(
            "The 'claude' command was not found"
        ) from exc

    if result.returncode != 0:
        error = result.stderr.strip() or result.stdout.strip()
        raise RuntimeError(error or "Claude Code failed")

    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError(
            f"Claude returned invalid JSON: {result.stdout[:500]}"
        ) from exc

    answer = payload.get("result")

    if not isinstance(answer, str):
        raise RuntimeError("Claude response did not contain a result")

    return answer


def validate_key(authorization: str | None) -> None:
    expected = f"Bearer {BRIDGE_KEY}"

    if authorization != expected:
        raise HTTPException(status_code=401, detail="Invalid API key")


@app.get("/v1/models")
async def models(
    authorization: str | None = Header(default=None),
) -> dict[str, Any]:
    validate_key(authorization)

    return {
        "object": "list",
        "data": [
            {"id": "claude-sonnet", "object": "model"},
            {"id": "claude-opus", "object": "model"},
            {"id": "claude-haiku", "object": "model"},
        ],
    }


@app.post("/v1/chat/completions")
async def chat_completions(
    request: Request,
    authorization: str | None = Header(default=None),
):
    validate_key(authorization)
    body = await request.json()

    messages = body.get("messages")
    if not isinstance(messages, list) or not messages:
        raise HTTPException(
            status_code=400,
            detail="'messages' must be a non-empty array",
        )

    requested_model = str(body.get("model", "claude-sonnet"))
    stream = bool(body.get("stream", False))
    completion_id = f"chatcmpl-{uuid.uuid4().hex}"

    async def get_answer() -> str:
        async with semaphore:
            try:
                return await asyncio.to_thread(
                    invoke_claude,
                    messages,
                    requested_model,
                )
            except RuntimeError as exc:
                raise HTTPException(
                    status_code=502,
                    detail=str(exc),
                ) from exc

    if not stream:
        answer = await get_answer()

        return {
            "id": completion_id,
            "object": "chat.completion",
            "created": int(time.time()),
            "model": requested_model,
            "choices": [
                {
                    "index": 0,
                    "message": {
                        "role": "assistant",
                        "content": answer,
                    },
                    "finish_reason": "stop",
                }
            ],
            "usage": {
                "prompt_tokens": 0,
                "completion_tokens": 0,
                "total_tokens": 0,
            },
        }

    async def event_stream():
        answer = await get_answer()

        content_chunk = {
            "id": completion_id,
            "object": "chat.completion.chunk",
            "created": int(time.time()),
            "model": requested_model,
            "choices": [
                {
                    "index": 0,
                    "delta": {
                        "role": "assistant",
                        "content": answer,
                    },
                    "finish_reason": None,
                }
            ],
        }

        final_chunk = {
            "id": completion_id,
            "object": "chat.completion.chunk",
            "created": int(time.time()),
            "model": requested_model,
            "choices": [
                {
                    "index": 0,
                    "delta": {},
                    "finish_reason": "stop",
                }
            ],
        }

        yield f"data: {json.dumps(content_chunk)}\n\n"
        yield f"data: {json.dumps(final_chunk)}\n\n"
        yield "data: [DONE]\n\n"

    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
    )
