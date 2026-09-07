import logging
import time
import os
from datetime import datetime, timezone
from fastapi import FastAPI, HTTPException, UploadFile, File
from pydantic import BaseModel
from typing import Dict, Any
from llama_cpp import Llama
from sqlalchemy import create_engine, Column, Integer, String, DateTime
from sqlalchemy.orm import declarative_base, sessionmaker
from faster_whisper import WhisperModel

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
    logger.info("Inicializando Llama-cpp (GPU/Vulkan)...")
    llm = Llama(
        model_path="backend/dolphin-2.9-llama3-8b-q4_K_M.gguf",
        chat_format="chatml",
        n_gpu_layers=-1,
        n_threads=6,
        n_batch=512,
        n_ctx=8192,
        verbose=False,
    )
    logger.info("LLM carregado com sucesso.")

    logger.info("Inicializando Faster-Whisper (CPU)...")
    whisper_model = WhisperModel("tiny", device="cpu", compute_type="int8")
    logger.info("Whisper carregado com sucesso.")
except Exception as e:
    logger.error(f"Falha ao carregar modelos de IA: {e}")
    raise e


class CognitiveRequest(BaseModel):
    npc_name: str
    system_prompt: str
    world_state: Dict[str, Any]
    stimulus: str
    temperature: float


@app.post("/transcribe_voice")
async def transcribe_voice(file: UploadFile = File(...)):
    try:
        temp_path = f"backend/temp_{file.filename}"
        with open(temp_path, "wb") as f:
            f.write(await file.read())

        segments, _ = whisper_model.transcribe(temp_path, beam_size=5, language="pt")
        text = "".join([segment.text for segment in segments]).strip()

        os.remove(temp_path)
        logger.info(f"[WHISPER TRANSCRICAO]: {text}")
        return {"text": text}
    except Exception as e:
        logger.error(f"Erro de Transcricao: {e}")
        raise HTTPException(status_code=500, detail="Erro no processamento de voz")


@app.post("/process_cognition")
async def process_cognition(req: CognitiveRequest):
    logger.info(f"--- Requisicao de Cognicao: {req.npc_name} ---")
    db = SessionLocal()

    world_context = f"[DADOS ONISCIENTES DO MUNDO]\n{req.world_state}\n\n[ESTIMULO SENSORIAL IMEDIATO]\n{req.stimulus}"
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
            messages=messages,
            temperature=req.temperature,
            max_tokens=256,
            response_format={"type": "json_object"},
        )
    except Exception as e:
        logger.error(f"Erro no LLM: {e}")
        db.close()
        raise HTTPException(status_code=500, detail="Erro interno do LLM")

    generation_time = time.time() - start_time
    action_thought = response["choices"][0]["message"]["content"]

    db.add(Memory(npc_name=req.npc_name, role="user", content=req.stimulus))
    db.add(Memory(npc_name=req.npc_name, role="assistant", content=action_thought))
    db.commit()
    db.close()

    logger.info(f"Tempo: {generation_time:.2f}s | Pensamento: {action_thought}")
    return {"npc_name": req.npc_name, "action_thought": action_thought}
