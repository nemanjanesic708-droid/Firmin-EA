from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy import String, Integer, Float, DateTime, JSON, ForeignKey
from sqlalchemy.dialects.postgresql import UUID
import uuid, datetime

from db import Base

class Bot(Base):
    __tablename__ = "bots"
    id: Mapped[str] = mapped_column(String, primary_key=True)
    name: Mapped[str | None] = mapped_column(String, nullable=True)
    api_key: Mapped[str] = mapped_column(String, nullable=False)
    vm_tag: Mapped[str | None] = mapped_column(String, nullable=True)
    created_at: Mapped[datetime.datetime] = mapped_column(DateTime, default=datetime.datetime.utcnow)

class Heartbeat(Base):
    __tablename__ = "heartbeats"
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    bot_id: Mapped[str] = mapped_column(String, ForeignKey("bots.id"))
    ts: Mapped[datetime.datetime] = mapped_column(DateTime, default=datetime.datetime.utcnow, index=True)
    spread: Mapped[float] = mapped_column(Float)
    equity: Mapped[float] = mapped_column(Float)
    features: Mapped[dict] = mapped_column(JSON)

class Decision(Base):
    __tablename__ = "decisions"
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    bot_id: Mapped[str] = mapped_column(String, ForeignKey("bots.id"))
    ts: Mapped[datetime.datetime] = mapped_column(DateTime, default=datetime.datetime.utcnow, index=True)
    action: Mapped[str] = mapped_column(String)     # OPEN | SKIP
    symbol: Mapped[str | None] = mapped_column(String, nullable=True)
    side: Mapped[str | None] = mapped_column(String, nullable=True)  # BUY | SELL
    lot: Mapped[float | None] = mapped_column(Float, nullable=True)
    sl_pips: Mapped[int | None] = mapped_column(Integer, nullable=True)
    tp_pips: Mapped[int | None] = mapped_column(Integer, nullable=True)
    expires_at: Mapped[datetime.datetime | None] = mapped_column(DateTime, nullable=True)
    confidence: Mapped[float | None] = mapped_column(Float, nullable=True)
    model_version: Mapped[str | None] = mapped_column(String, nullable=True)
    experiment_group: Mapped[str | None] = mapped_column(String, nullable=True)

class Execution(Base):
    __tablename__ = "executions"
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    decision_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("decisions.id"), nullable=True)
    bot_id: Mapped[str] = mapped_column(String, ForeignKey("bots.id"))
    status: Mapped[str] = mapped_column(String)  # SENT | OPENED | CLOSED | REJECTED
    order_ticket: Mapped[int | None] = mapped_column(Integer, nullable=True)
    entry_price: Mapped[float | None] = mapped_column(Float, nullable=True)
    exit_price: Mapped[float | None] = mapped_column(Float, nullable=True)
    pnl: Mapped[float | None] = mapped_column(Float, nullable=True)
    mfe: Mapped[float | None] = mapped_column(Float, nullable=True)
    mae: Mapped[float | None] = mapped_column(Float, nullable=True)
    closed_ts: Mapped[datetime.datetime | None] = mapped_column(DateTime, nullable=True)
