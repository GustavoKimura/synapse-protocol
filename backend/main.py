import logging
import time
from datetime import datetime, timezone
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import Dict, Any
from llama_cpp import Llama
from sqlalchemy import create_engine, Column, Integer, String, DateTime
from sqlalchemy.orm import declarative_base, sessionmaker

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)

engine = create_engine(
    "sqlite:///backend/synapse.db", connect_args={"check_same_thread": False}
)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


class Memory(Base):
    __tablename__ = "npc_memories"
    id = Column(Integer, primary_key=True, index=True)
    npc_name = Column(String, index=True)
    role = Column(String)
    content = Column(String)
    timestamp = Column(DateTime, default=lambda: datetime.now(timezone.utc))


Base.metadata.create_all(bind=engine)

app = FastAPI()

try:
    llm = Llama(
        model_path="backend/dolphin-2.9-llama3-8b-q4_K_M.gguf",
        chat_format="chatml",
        n_gpu_layers=-1,
        n_threads=6,
        n_batch=512,
        n_ctx=8192,
        verbose=False,
    )
    logger.info("Model loaded successfully.")
except Exception as e:
    logger.error(f"Failed to load model: {e}")
    raise e


class CognitiveRequest(BaseModel):
    npc_name: str
    system_prompt: str
    world_state: Dict[str, Any]
    stimulus: str
    temperature: float


@app.post("/process_cognition")
async def process_cognition(req: CognitiveRequest):
    logger.info(f"--- Cognition Request: {req.npc_name} ---")

    db = SessionLocal()

    world_context = f"[WORLD STATE OMNISCIENT DATA]\n{req.world_state}\n\n[IMMEDIATE SENSORY INPUT]\n{req.stimulus}"

    messages = [{"role": "system", "content": req.system_prompt}]

    history = (
        db.query(Memory)
        .filter(Memory.npc_name == req.npc_name)
        .order_by(Memory.timestamp.asc())
        .limit(10)
        .all()
    )
    for mem in history:
        messages.append({"role": mem.role, "content": mem.content})

    messages.append({"role": "user", "content": world_context})

    start_time = time.time()
    try:
        response = llm.create_chat_completion(
            messages=messages, temperature=req.temperature, max_tokens=256
        )
    except Exception as e:
        logger.error(f"LLM Error: {e}")
        db.close()
        raise HTTPException(status_code=500, detail="Internal LLM Error")

    generation_time = time.time() - start_time
    action_thought = response["choices"][0]["message"]["content"]

    user_mem = Memory(npc_name=req.npc_name, role="user", content=req.stimulus)
    asst_mem = Memory(npc_name=req.npc_name, role="assistant", content=action_thought)
    db.add(user_mem)
    db.add(asst_mem)
    db.commit()
    db.close()

    usage = response.get("usage", {})
    completion_tokens = usage.get("completion_tokens", 0)
    total_tokens = usage.get("total_tokens", 0)
    tps = completion_tokens / generation_time if generation_time > 0 else 0

    logger.info(
        f"Time: {generation_time:.2f}s | Speed: {tps:.2f} tps | Tokens: {total_tokens}"
    )
    logger.info(f"Thought: {action_thought}")

    return {"npc_name": req.npc_name, "action_thought": action_thought}
