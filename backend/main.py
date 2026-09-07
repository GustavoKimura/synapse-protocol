import logging
import time
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from llama_cpp import Llama

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)

app = FastAPI()

logger.info("Initializing Llama-cpp engine with Vulkan acceleration...")
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
    stimulus: str
    temperature: float


@app.post("/process_cognition")
async def process_cognition(req: CognitiveRequest):
    logger.info(f"--- New Cognition Request for NPC: {req.npc_name} ---")
    logger.info(f"Stimulus: {req.stimulus}")
    logger.info(f"Temperature: {req.temperature}")

    messages = [
        {"role": "system", "content": req.system_prompt},
        {"role": "user", "content": req.stimulus},
    ]

    start_time = time.time()
    try:
        response = llm.create_chat_completion(
            messages=messages, temperature=req.temperature, max_tokens=256
        )
    except Exception as e:
        logger.error(f"Error during LLM generation: {e}")
        raise HTTPException(status_code=500, detail="Internal LLM Error")

    end_time = time.time()
    generation_time = end_time - start_time

    action_thought = response["choices"][0]["message"]["content"]
    usage = response.get("usage", {})
    completion_tokens = usage.get("completion_tokens", 0)
    total_tokens = usage.get("total_tokens", 0)
    tps = completion_tokens / generation_time if generation_time > 0 else 0

    logger.info(f"Generation completed in {generation_time:.2f} seconds.")
    logger.info(f"Tokens - Completion: {completion_tokens} | Total: {total_tokens}")
    logger.info(f"Speed: {tps:.2f} tokens/sec")
    logger.info(f"Resulting Thought: {action_thought}")
    logger.info("---------------------------------------------------")

    return {"npc_name": req.npc_name, "action_thought": action_thought}
