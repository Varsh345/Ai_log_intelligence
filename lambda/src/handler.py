"""
AI Log Intelligence — Lambda Handler
Fetches ERROR/WARN log events, deduplicates, calls Ollama on EC2,
parses JSON analysis, publishes enriched alert to SNS.
"""

import json
import logging
import os
import re
import time
import urllib.error
import urllib.request
from collections import defaultdict
from datetime import datetime, timezone
from hashlib import md5

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# ── Environment Variables ────────────────────────────────────────────────────
LOG_GROUP_NAME      = os.environ["LOG_GROUP_NAME"]
SNS_TOPIC_ARN       = os.environ["SNS_TOPIC_ARN"]
OLLAMA_URL          = os.environ["OLLAMA_URL"]
IDEMPOTENCY_TABLE   = os.environ.get("IDEMPOTENCY_TABLE_NAME", "")

# ── Tunables ─────────────────────────────────────────────────────────────────
LOOKBACK_MINUTES    = 15
MAX_EVENTS          = 500
TOP_GROUPS          = 5
OLLAMA_MODEL        = "phi3:mini"
OLLAMA_TIMEOUT      = 110          # seconds (Lambda timeout is 120)
RATE_LIMIT_SECONDS  = 300          # min gap between runs
IDEMPOTENCY_TTL     = 3600         # seconds; DynamoDB auto-expiry

# ── AWS Clients ───────────────────────────────────────────────────────────────
logs_client = boto3.client("logs")
sns_client  = boto3.client("sns")
ddb_client  = boto3.client("dynamodb") if IDEMPOTENCY_TABLE else None


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

def fetch_log_events(lookback_minutes: int = LOOKBACK_MINUTES, max_events: int = MAX_EVENTS) -> list[str]:
    """Pull recent log events that contain ERROR or WARN."""
    now_ms     = int(time.time() * 1000)
    start_ms   = now_ms - lookback_minutes * 60 * 1000
    messages   = []
    kwargs = dict(
        logGroupName  = LOG_GROUP_NAME,
        startTime     = start_ms,
        endTime       = now_ms,
        filterPattern = "?ERROR ?WARN",
        limit         = min(max_events, 10000),
    )
    try:
        while len(messages) < max_events:
            resp   = logs_client.filter_log_events(**kwargs)
            events = resp.get("events", [])
            messages.extend(e["message"].strip() for e in events if e.get("message"))
            token  = resp.get("nextToken")
            if not token or len(messages) >= max_events:
                break
            kwargs["nextToken"] = token
    except Exception as exc:
        logger.error("Error fetching log events: %s", exc)
    return messages[:max_events]


def normalize(msg: str) -> str:
    """Strip timestamps, IDs, numbers so similar lines hash to the same key."""
    msg = re.sub(r"\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}[\.,\d]*Z?", "", msg)
    msg = re.sub(r"\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b", "<UUID>", msg, flags=re.I)
    msg = re.sub(r"\b\d+\b", "<N>", msg)
    msg = re.sub(r"\s+", " ", msg)
    return msg.strip()


def deduplicate(messages: list[str], top_n: int = TOP_GROUPS) -> list[dict]:
    """Group by normalized key, keep top N by count."""
    groups: dict[str, dict] = defaultdict(lambda: {"count": 0, "samples": []})
    for msg in messages:
        key = normalize(msg)
        grp = groups[key]
        grp["count"] += 1
        if len(grp["samples"]) < 3:
            grp["samples"].append(msg)

    sorted_groups = sorted(groups.items(), key=lambda x: x[1]["count"], reverse=True)
    return [{"pattern": k, **v} for k, v in sorted_groups[:top_n]]


def batch_hash(groups: list[dict]) -> str:
    payload = json.dumps([g["pattern"] for g in groups], sort_keys=True)
    return md5(payload.encode()).hexdigest()


# ── DynamoDB idempotency ──────────────────────────────────────────────────────

def check_idempotency(b_hash: str) -> bool:
    """Return True if this batch was already processed recently (skip it)."""
    if not ddb_client:
        return False
    try:
        resp = ddb_client.get_item(
            TableName=IDEMPOTENCY_TABLE,
            Key={"id": {"S": "last_run"}},
        )
        item = resp.get("Item", {})
        if not item:
            return False
        stored_hash = item.get("batch_hash", {}).get("S", "")
        stored_ts   = float(item.get("ts", {}).get("N", "0"))
        age         = time.time() - stored_ts
        if stored_hash == b_hash and age < RATE_LIMIT_SECONDS:
            logger.info("Idempotency hit: same batch, age=%.0fs < %ss — skipping", age, RATE_LIMIT_SECONDS)
            return True
        if age < RATE_LIMIT_SECONDS:
            logger.info("Rate limit: last run %.0fs ago < %ss — skipping", age, RATE_LIMIT_SECONDS)
            return True
    except Exception as exc:
        logger.warning("DynamoDB check failed (proceeding): %s", exc)
    return False


def save_idempotency(b_hash: str) -> None:
    if not ddb_client:
        return
    now = time.time()
    try:
        ddb_client.put_item(
            TableName=IDEMPOTENCY_TABLE,
            Item={
                "id":         {"S": "last_run"},
                "batch_hash": {"S": b_hash},
                "ts":         {"N": str(now)},
                "ttl":        {"N": str(int(now + IDEMPOTENCY_TTL))},
            },
        )
    except Exception as exc:
        logger.warning("DynamoDB save failed: %s", exc)


# ── Ollama ────────────────────────────────────────────────────────────────────

def build_prompt(groups: list[dict]) -> str:
    lines = []
    for g in groups:
        lines.append(f"  Pattern ({g['count']}x): {g['pattern']}")
        if g["samples"]:
            lines.append(f"    Example: {g['samples'][0]}")
    error_block = "\n".join(lines)

    return f"""You are a senior SRE analyzing application log errors.
Below are deduplicated ERROR/WARN log patterns from the last 15 minutes.

{error_block}

Respond ONLY with valid JSON.
Do NOT include explanations.
Do NOT include markdown.
Do NOT include code blocks.

Return JSON exactly in this schema:

{{
  "error_summary": "<one paragraph summary>",
  "root_cause": "<probable root cause>",
  "recommended_fix": "<actionable steps to fix>",
  "severity": "LOW|MEDIUM|HIGH"
}}"""


def call_ollama(prompt: str) -> str:
    """POST to Ollama /api/generate and return raw response text."""
    payload = json.dumps({
        "model":  OLLAMA_MODEL,
        "prompt": prompt,
        "stream": False,
        "format": "json",
        "options": {
            "num_predict": 200,
        },
    }).encode()

    req = urllib.request.Request(
        OLLAMA_URL,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=OLLAMA_TIMEOUT) as resp:
        body = json.loads(resp.read().decode())
    return body.get("response", "")


def parse_response(raw: str) -> dict:
    """Extract JSON object from model output; fall back to safe defaults. Prefers valid JSON."""
    s = (raw or "").strip()
    if not s:
        logger.warning("Empty Ollama response; using fallback.")
        return {
            "error_summary":   "No response from model.",
            "root_cause":      "Unable to determine.",
            "recommended_fix": "Review logs manually.",
            "severity":        "MEDIUM",
        }

    # Try direct parse first (prefer valid JSON)
    try:
        return json.loads(s)
    except json.JSONDecodeError:
        pass

    # Strip markdown code fences if present
    for prefix in ("```json", "```"):
        if s.startswith(prefix):
            s = s[len(prefix):].lstrip()
        if s.endswith("```"):
            s = s[:-3].rstrip()
    try:
        return json.loads(s)
    except json.JSONDecodeError:
        pass

    # Find outermost {...} block (handles nested braces)
    depth, start, end = 0, -1, -1
    for i, c in enumerate(s):
        if c == "{":
            if depth == 0:
                start = i
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                end = i + 1
                break
    if start >= 0 and end > start:
        try:
            return json.loads(s[start:end])
        except json.JSONDecodeError:
            pass

    logger.warning("Could not parse Ollama response as JSON; using fallback.")
    return {
        "error_summary":   s[:500],
        "root_cause":      "Unable to determine.",
        "recommended_fix":  "Review logs manually.",
        "severity":        "MEDIUM",
    }


def normalize_severity(sev: str) -> str:
    sev = sev.upper().strip()
    return sev if sev in {"LOW", "MEDIUM", "HIGH"} else "MEDIUM"


# ── SNS ───────────────────────────────────────────────────────────────────────

def publish_alert(analysis: dict, groups: list[dict]) -> None:
    severity = normalize_severity(analysis.get("severity", "MEDIUM"))
    subject  = f"[{severity}] AI Log Alert — {LOG_GROUP_NAME}"

    sample_errors = "\n".join(
        f"  [{g['count']}x] {g['samples'][0]}" for g in groups[:10] if g["samples"]
    )

    body = f"""
AI Log Intelligence Alert
=========================
Timestamp : {datetime.now(timezone.utc).isoformat()}
Log Group : {LOG_GROUP_NAME}
Severity  : {severity}

ERROR SUMMARY
-------------
{analysis.get('error_summary', 'N/A')}

ROOT CAUSE
----------
{analysis.get('root_cause', 'N/A')}

RECOMMENDED FIX
---------------
{analysis.get('recommended_fix', 'N/A')}

TOP ERROR PATTERNS (sample)
----------------------------
{sample_errors}
""".strip()

    sns_client.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject=subject[:100],
        Message=body,
    )
    logger.info("Alert published to SNS: %s", subject)


# ── Entry Point ───────────────────────────────────────────────────────────────

def handler(event, context):
    logger.info("Lambda invoked. Event: %s", json.dumps(event, default=str))

    # 1. Fetch log events
    messages = fetch_log_events()
    if not messages:
        logger.info("No ERROR/WARN events found — nothing to do.")
        return {"status": "no_events"}

    logger.info("Fetched %d log messages", len(messages))

    # 2. Deduplicate
    groups = deduplicate(messages)
    logger.info("Deduplicated into %d groups", len(groups))

    # 3. Idempotency check
    b_hash = batch_hash(groups)
    if check_idempotency(b_hash):
        return {"status": "skipped_idempotency"}

    # 4. Build prompt & call Ollama (retry once if model is cold)
    prompt = build_prompt(groups)
    logger.info("Calling Ollama at %s …", OLLAMA_URL)
    raw = ""
    for attempt in range(2):
        try:
            raw = call_ollama(prompt)
            break
        except Exception as exc:
            logger.warning("Ollama request failed (attempt %s): %s", attempt + 1, exc)
            if attempt < 1:
                logger.warning("Retrying Ollama request...")
                time.sleep(2)
    if raw:
        logger.info("Ollama raw response: %s", raw[:500])
    logger.info("Ollama response length: %s", len(raw) if raw else 0)

    # 5. Parse analysis
    analysis = parse_response(raw)
    analysis["severity"] = normalize_severity(analysis.get("severity", "MEDIUM"))

    # 6. Publish to SNS
    publish_alert(analysis, groups)

    # 7. Save idempotency state
    save_idempotency(b_hash)

    return {"status": "ok", "severity": analysis["severity"], "groups": len(groups)}
