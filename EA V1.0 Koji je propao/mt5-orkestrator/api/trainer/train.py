import os, datetime, joblib, numpy as np
from sqlalchemy import select
from db import SessionLocal
from models import Heartbeat, Decision, Execution
from sklearn.linear_model import LogisticRegression

# Very simple demo trainer: we fabricate labels from executions:
# label=1 if pnl>0 else 0, features from last heartbeat at decision time.
# Feature vector: [spread, atr (if any), rsi (if any), hour]
MODEL_PATH = os.path.join(os.path.dirname(__file__), "..", "models", "model.pkl")

def main():
    X, y = [], []
    with SessionLocal() as db:
        # join decisions and executions by decision_id and take those that are CLOSED with pnl
        execs = db.query(Execution).filter(Execution.status=="CLOSED", Execution.pnl != None).limit(5000).all()
        for ex in execs:
            # find decision time close to execution
            dec = db.query(Decision).filter(Decision.id==ex.decision_id).first()
            if not dec:
                continue
            # find nearest heartbeat before decision
            hb = db.query(Heartbeat).filter(Heartbeat.bot_id==dec.bot_id, Heartbeat.ts <= dec.ts).order_by(Heartbeat.ts.desc()).first()
            if not hb:
                continue
            features = dict(hb.features or {})
            spread = float(hb.spread or 0.0)
            atr = float(features.get("atr", 0.0))
            rsi = float(features.get("rsi", 50.0))
            # naive hour from decision time
            hour = dec.ts.hour if dec.ts else 12
            X.append([spread, atr, rsi, hour])
            y.append(1 if (ex.pnl or 0.0) > 0 else 0)
    if len(X) < 50:
        print("Not enough samples to train (need >=50). Got:", len(X))
        return 1
    X = np.array(X); y = np.array(y)
    clf = LogisticRegression(max_iter=1000)
    clf.fit(X, y)
    os.makedirs(os.path.dirname(MODEL_PATH), exist_ok=True)
    joblib.dump(clf, MODEL_PATH)
    print("Model trained and saved to", MODEL_PATH)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
