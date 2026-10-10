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
COPY wheels/sm120/sageattention-2.2.0-cp312-cp312-linux_x86_64.whl /opt/chud-h3/wheels/sm120/sageattention-2.2.0-cp312-cp312-linux_x86_64.whl

RUN chmod +x /opt/chud-h3/install-nodes.sh /opt/chud-h3/docker-start.sh /opt/chud-h3/download-models.py /opt/chud-h3/restore-v21.sh /opt/chud-h3/audit-v21.sh /opt/chud-h3/assemble-workflow.sh /opt/chud-h3/v24-module-manager.sh /opt/chud-h3/setup-thai-tts.sh
RUN /opt/chud-h3/assemble-workflow.sh /opt/chud-h3/workflows/chunks /opt/chud-h3/workflows/minimaxH3SEEDHUNTERLatent_v21.json
RUN /opt/chud-h3/install-nodes.sh

RUN python3.12 -m pip install --no-cache-dir -c /opt/comfyui-runtime-constraints.txt \
    "comfy-kitchen==0.2.37" \
    "comfy-aimdo==0.5.5" \
    "comfyui-frontend-package==1.53.10" \
    "huggingface-hub==1.27.0" \
    "hf-xet==1.6.0"

RUN python3.12 -m pip install --no-cache-dir --force-reinstall --no-deps /opt/chud-h3/wheels/sm120/sageattention-2.2.0-cp312-cp312-linux_x86_64.whl
ENTRYPOINT ["/opt/chud-h3/docker-start.sh"]
