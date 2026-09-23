FROM runpod/comfyui:1.4.6-cuda13.0

USER root

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV HF_XET_HIGH_PERFORMANCE=1
ENV HF_HUB_DISABLE_XET=0

WORKDIR /opt/chud-h3

COPY nodes.lock /opt/chud-h3/nodes.lock
COPY runtime.lock /opt/chud-h3/runtime.lock
COPY model_sources.tsv /opt/chud-h3/model_sources.tsv
COPY download-models.py /opt/chud-h3/download-models.py
COPY install-nodes.sh /opt/chud-h3/install-nodes.sh
COPY docker-start.sh /opt/chud-h3/docker-start.sh

COPY wheels/sm120/sageattention-2.2.0-cp312-cp312-linux_x86_64.whl \
     /opt/chud-h3/wheels/sm120/sageattention.whl

RUN chmod +x \
    /opt/chud-h3/install-nodes.sh \
    /opt/chud-h3/docker-start.sh \
    /opt/chud-h3/download-models.py

RUN /opt/chud-h3/install-nodes.sh

RUN python3.12 -m pip install \
    --no-cache-dir \
    -c /opt/comfyui-runtime-constraints.txt \
    --force-reinstall \
    "comfy-kitchen==0.2.35" \
    "comfy-aimdo==0.5.5" \
    "comfyui-frontend-package==1.53.6" \
    "huggingface-hub==1.27.0" \
    "
