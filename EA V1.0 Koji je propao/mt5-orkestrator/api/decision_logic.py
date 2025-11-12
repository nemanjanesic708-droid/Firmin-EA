import os, datetime, random, math, json, joblib
from typing import Optional

SPREAD_LIMIT = float(os.getenv("SPREAD_LIMIT", "20"))  # points
DEFAULT_SYMBOL = os.getenv("DEFAULT_SYMBOL", "EURUSD")
DEFAULT_LOT = float(os.getenv("DEFAULT_LOT", "0.30"))
DEFAULT_SL_PIPS = int(os.getenv("DEFAULT_SL_PIPS", "5"))
DEFAULT_TP_PIPS = int(os.getenv("DEFAULT_TP_PIPS", "10"))
USE_ML = os.getenv("USE_ML", "false").lower() == "true"

MODEL_PATH = os.path.join(os.path.dirname(__file__), "models", "model.pkl")
_model = None

def load_model():
    global _model
    if os.path.exists(MODEL_PATH):
        try:
            _model = joblib.load(MODEL_PATH)
        except Exception as e:
            print("Model load failed:", e)

def score_and_decide(latest_features: dict) -> dict:
    """Return a decision dict. If ML enabled and model exists, use it; else rule-based."""
    now = datetime.datetime.utcnow()
    base = {
        "action": "SKIP",
        "symbol": DEFAULT_SYMBOL,
        "side": "BUY",
        "lot": DEFAULT_LOT,
        "sl_pips": DEFAULT_SL_PIPS,
        "tp_pips": DEFAULT_TP_PIPS,
        "expires_at": (now + datetime.timedelta(seconds=10)).isoformat() + "Z",
        "confidence": 0.5,
        "model_version": "baseline",
        "experiment_group": "A",
    }

    spread = latest_features.get("spread", 999)
    session = latest_features.get("session", "UNK")

    # simple guardrails
    if spread > SPREAD_LIMIT:
        return base  # SKIP

    # Simple baseline: favor BUY during LDN/NY sessions, SELL otherwise (toy example)
    side = "BUY" if session in ("LDN", "NY") else "SELL"
    base["side"] = side
    base["action"] = "OPEN"
    base["confidence"] = 0.55
    base["experiment_group"] = "A"

    if USE_ML and _model is not None:
        # Expect vector: [spread, atr, rsi, hour]
        v = [
            float(latest_features.get("spread", 0)),
            float(latest_features.get("atr", 0)),
            float(latest_features.get("rsi", 50)),
            float(latest_features.get("hour", 12)),
        ]
        prob = float(_model.predict_proba([v])[0][1])  # prob of "win"
        base["confidence"] = prob
        base["model_version"] = "ml-v1"
        base["experiment_group"] = "B"
        # threshold
        if prob >= 0.58:
            base["action"] = "OPEN"
        else:
            base["action"] = "SKIP"
    return base
