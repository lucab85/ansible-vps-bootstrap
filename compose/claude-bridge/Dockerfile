FROM python:3.11-slim

RUN pip install --no-cache-dir fastapi==0.115.* "uvicorn[standard]==0.32.*"

# Same binary already proven working on the host (v2.1.258) - only depends
# on glibc/libpthread/libm/librt/libdl, all present in this base image, so
# no need to re-run the installer script inside the build.
COPY claude-bin /usr/local/bin/claude
RUN chmod +x /usr/local/bin/claude

COPY claude_openai_bridge.py /app/claude_openai_bridge.py
WORKDIR /app

EXPOSE 8000
CMD ["uvicorn", "claude_openai_bridge:app", "--host", "0.0.0.0", "--port", "8000"]
