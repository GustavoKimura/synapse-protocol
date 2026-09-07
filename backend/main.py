import logging
import time
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import Dict, List, Any
from llama_cpp import Llama

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)

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


npc_memory: Dict[str, List[Dict[str, str]]] = {}


@app.post("/process_cognition")
async def process_cognition(req: CognitiveRequest):
    logger.info(f"--- Cognition Request: {req.npc_name} ---")

    if req.npc_name not in npc_memory:
        npc_memory[req.npc_name] = []

    world_context = f"[WORLD STATE OMNISCIENT DATA]\n{req.world_state}\n\n[IMMEDIATE SENSORY INPUT]\n{req.stimulus}"

    messages = [{"role": "system", "content": req.system_prompt}]
    messages.extend(npc_memory[req.npc_name][-10:])
    messages.append({"role": "user", "content": world_context})

    start_time = time.time()
    try:
        response = llm.create_chat_completion(
            messages=messages, temperature=req.temperature, max_tokens=256
        )
    except Exception as e:
        logger.error(f"LLM Error: {e}")
        raise HTTPException(status_code=500, detail="Internal LLM Error")

    generation_time = time.time() - start_time
    action_thought = response["choices"][0]["message"]["content"]

    npc_memory[req.npc_name].append({"role": "user", "content": req.stimulus})
    npc_memory[req.npc_name].append({"role": "assistant", "content": action_thought})

    usage = response.get("usage", {})
    completion_tokens = usage.get("completion_tokens", 0)
    total_tokens = usage.get("total_tokens", 0)
    tps = completion_tokens / generation_time if generation_time > 0 else 0

    logger.info(
        f"Time: {generation_time:.2f}s | Speed: {tps:.2f} tps | Tokens: {total_tokens}"
    )
    logger.info(f"Thought: {action_thought}")

    return {"npc_name": req.npc_name, "action_thought": action_thought}
