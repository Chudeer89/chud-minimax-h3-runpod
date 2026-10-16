# SageAttention 2.x for sm89 (L40S / L40 / RTX 6000 Ada) + sm120 (Blackwell), built without a GPU against the
# runtime's torch 2.10.0+cu130 / Python 3.12. The old sm120-only wheel made every Sage CUDA kernel fail on the
# L40S with "no kernel image" (2026-10-16), so the memory-efficient Sage patch of the upscale pass could not run.
FROM nvidia/cuda:13.0.0-devel-ubuntu24.04 AS sage
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update -qq && apt-get install -y -qq python3.12 python3.12-venv python3.12-dev git && rm -rf /var/lib/apt/lists/*
RUN python3.12 -m venv /venv && /venv/bin/pip install -q --no-cache-dir --upgrade pip setuptools wheel ninja packaging     && /venv/bin/pip install -q --no-cache-dir torch==2.10.0 --index-url https://download.pytorch.org/whl/cu130
RUN git clone https://github.com/thu-ml/SageAttention.git /src && cd /src && git checkout d1a57a5
RUN cd /src && TORCH_CUDA_ARCH_LIST="8.9;12.0" MAX_JOBS=2 EXT_PARALLEL=1 NVCC_APPEND_FLAGS="--threads 2"     /venv/bin/python setup.py bdist_wheel && ls -la dist

FROM runpod/comfyui:1.4.6-cuda13.0

USER root
ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV HF_XET_HIGH_PERFORMANCE=1
ENV HF_HUB_DISABLE_XET=0
WORKDIR /opt/chud-h3

COPY nodes.lock /opt/chud-h3/nodes.lock
COPY nodes.v24.optional.lock /opt/chud-h3/nodes.v24.optional.lock
COPY runtime.lock /opt/chud-h3/runtime.lock
COPY model_sources.tsv /opt/chud-h3/model_sources.tsv
COPY model_sources_civitai.tsv /opt/chud-h3/model_sources_civitai.tsv
COPY download-models.py /opt/chud-h3/download-models.py
COPY install-nodes.sh /opt/chud-h3/install-nodes.sh
COPY v24-module-manager.sh /opt/chud-h3/v24-module-manager.sh
COPY setup-thai-tts.sh /opt/chud-h3/setup-thai-tts.sh
COPY thai_tts_server.py /opt/chud-h3/thai_tts_server.py
COPY docker-start.sh /opt/chud-h3/docker-start.sh
COPY restore-v21.sh /opt/chud-h3/restore-v21.sh
COPY audit-v21.sh /opt/chud-h3/audit-v21.sh
COPY assemble-workflow.sh /opt/chud-h3/assemble-workflow.sh
COPY workflows /opt/chud-h3/workflows
COPY custom_nodes/ChuD-ThaiTTS /opt/comfyui-baked/custom_nodes/ChuD-ThaiTTS

RUN chmod +x /opt/chud-h3/install-nodes.sh /opt/chud-h3/docker-start.sh /opt/chud-h3/download-models.py /opt/chud-h3/restore-v21.sh /opt/chud-h3/audit-v21.sh /opt/chud-h3/assemble-workflow.sh /opt/chud-h3/v24-module-manager.sh /opt/chud-h3/setup-thai-tts.sh
RUN /opt/chud-h3/assemble-workflow.sh /opt/chud-h3/workflows/chunks /opt/chud-h3/workflows/minimaxH3SEEDHUNTERLatent_v21.json
RUN /opt/chud-h3/install-nodes.sh

RUN python3.12 -m pip install --no-cache-dir -c /opt/comfyui-runtime-constraints.txt \
    "comfy-kitchen==0.2.37" \
    "comfy-aimdo==0.5.5" \
    "comfyui-frontend-package==1.53.10" \
    "huggingface-hub==1.27.0" \
    "hf-xet==1.6.0"

COPY --from=sage /src/dist/ /opt/chud-h3/wheels/sage/
RUN python3.12 -m pip install --no-cache-dir --force-reinstall --no-deps /opt/chud-h3/wheels/sage/*.whl
ENTRYPOINT ["/opt/chud-h3/docker-start.sh"]
