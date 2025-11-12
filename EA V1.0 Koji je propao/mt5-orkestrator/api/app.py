import os, datetime, uuid
from fastapi import FastAPI, Header, HTTPException, Query
from pydantic import BaseModel
from typing import Optional
from db import SessionLocal, init_db
from models import Bot, Heartbeat, Decision, Execution
from sqlalchemy import select, desc
from decision_logic import score_and_decide, load_model

app = FastAPI(title="MT5 Orchestrator", version="0.1.0")

ADMIN_KEY = os.getenv("ADMIN_KEY", "changeme-admin")

def seed_bots(db):
    # Read three bots from env
    for i in (1,2,3):
        bid = os.getenv(f"BOT_{i}_ID")
        key = os.getenv(f"BOT_{i}_KEY")
        if bid and key:
            if db.get(Bot, bid) is None:
                db.add(Bot(id=bid, api_key=key, name=f"Bot {i}"))
    db.commit()

class HeartbeatIn(BaseModel):
    bot_id: str
    ts: Optional[datetime.datetime] = None
    spread: float
    equity: float
    features: dict = {}

class DecisionOut(BaseModel):
    id: str
    bot_id: str
    ts: datetime.datetime
    action: str
    symbol: Optional[str] = None
    side: Optional[str] = None
    lot: Optional[float] = None
    sl_pips: Optional[int] = None
    tp_pips: Optional[int] = None
    expires_at: Optional[datetime.datetime] = None
    confidence: Optional[float] = None
    model_version: Optional[str] = None
    experiment_group: Optional[str] = None

class ExecutionIn(BaseModel):
    decision_id: Optional[str] = None
    bot_id: str
    status: str
    order_ticket: Optional[int] = None
    entry_price: Optional[float] = None
    exit_price: Optional[float] = None
    pnl: Optional[float] = None
    mfe: Optional[float] = None
    mae: Optional[float] = None
    closed_ts: Optional[datetime.datetime] = None
    extra: dict = {}

def auth_bot(db, bot_id: str, authorization: Optional[str]):
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(401, "Missing Authorization")
    token = authorization.split(" ",1)[1]
    bot = db.get(Bot, bot_id)
    if not bot or bot.api_key != token:
        raise HTTPException(403, "Forbidden")
    return bot

@app.on_event("startup")
def on_startup():
    init_db()
    with SessionLocal() as db:
        seed_bots(db)
    load_model()

@app.get("/health")
def health():
    return {"ok": True, "ts": datetime.datetime.utcnow().isoformat()}

@app.post("/heartbeat")
def heartbeat(hb: HeartbeatIn, authorization: Optional[str] = Header(default=None)):
    with SessionLocal() as db:
        auth_bot(db, hb.bot_id, authorization)
        now = hb.ts or datetime.datetime.utcnow()
        rec = Heartbeat(bot_id=hb.bot_id, ts=now, spread=hb.spread, equity=hb.equity, features=hb.features)
        db.add(rec)
        db.commit()
    return {"ok": True}

@app.get("/decisions/next", response_model=DecisionOut)
def decisions_next(bot_id: str = Query(...), authorization: Optional[str] = Header(default=None)):
    with SessionLocal() as db:
        auth_bot(db, bot_id, authorization)
        # pull latest heartbeat to form features
        hb = db.execute(select(Heartbeat).where(Heartbeat.bot_id==bot_id).order_by(desc(Heartbeat.ts)).limit(1)).scalar_one_or_none()
        latest = hb.features if hb else {}
        if hb:
            latest["spread"] = hb.spread
            # naive features for demo
            # hour/session derived if not provided
            now = datetime.datetime.utcnow()
            latest.setdefault("hour", now.hour)
            if now.hour in range(7,15):
                latest.setdefault("session", "LDN")
            elif now.hour in range(12,21):
                latest.setdefault("session", "NY")
            else:
                latest.setdefault("session", "ASIA")

        d = score_and_decide(latest)
        dec = Decision(
            id=uuid.uuid4(),
            bot_id=bot_id,
            ts=datetime.datetime.utcnow(),
            action=d["action"],
            symbol=d.get("symbol"),
            side=d.get("side"),
            lot=d.get("lot"),
            sl_pips=d.get("sl_pips"),
            tp_pips=d.get("tp_pips"),
            expires_at=datetime.datetime.fromisoformat(d["expires_at"].replace("Z","")) if d.get("expires_at") else None,
            confidence=d.get("confidence"),
            model_version=d.get("model_version"),
            experiment_group=d.get("experiment_group"),
        )
        db.add(dec)
        db.commit()
        return DecisionOut(**{
            "id": str(dec.id),
            "bot_id": bot_id,
            "ts": dec.ts,
            "action": dec.action,
            "symbol": dec.symbol,
            "side": dec.side,
            "lot": dec.lot,
            "sl_pips": dec.sl_pips,
            "tp_pips": dec.tp_pips,
            "expires_at": dec.expires_at,
            "confidence": dec.confidence,
            "model_version": dec.model_version,
            "experiment_group": dec.experiment_group,
        })

@app.post("/executions")
def executions(ex: ExecutionIn, authorization: Optional[str] = Header(default=None)):
    with SessionLocal() as db:
        auth_bot(db, ex.bot_id, authorization)
        rec = Execution(
            decision_id=uuid.UUID(ex.decision_id) if ex.decision_id else None,
            bot_id=ex.bot_id,
            status=ex.status,
            order_ticket=ex.order_ticket,
            entry_price=ex.entry_price,
            exit_price=ex.exit_price,
            pnl=ex.pnl,
            mfe=ex.mfe,
            mae=ex.mae,
            closed_ts=ex.closed_ts
        )
        db.add(rec)
        db.commit()
    return {"ok": True}

# --- Admin endpoints ---
@app.post("/admin/train")
def admin_train(key: str):
    if key != ADMIN_KEY:
        raise HTTPException(403, "Forbidden")
    # run trainer
    import subprocess, sys
    cp = subprocess.run([sys.executable, "-m", "trainer.train"], capture_output=True, text=True)
    return {"ok": cp.returncode==0, "stdout": cp.stdout, "stderr": cp.stderr}
