FROM runpod/comfyui:1.4.6-cuda13.0

USER root

ENV DEBIAN_FRONTEND=noninteractive
ENV HF_XET_HIGH_PERFORMANCE=1
ENV HF_HUB_DISABLE_XET=0
ENV PYTHONUNBUFFERED=1

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        git \
        curl \
        wget \
        ffmpeg \
    && rm -rf /var/lib/apt/lists/*

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

RUN /workspace/runpod-slim/ComfyUI/.venv-cu128/bin/python -m pip install \
    --no-cach
