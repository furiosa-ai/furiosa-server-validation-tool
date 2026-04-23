FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV FURIOSA_SKIP_PERT_DEPLOY=1
ENV RUN_TESTS=diag,p2p,stress

ARG HF_TOKEN
RUN if [ -z "$HF_TOKEN" ]; then echo "ERROR: HF_TOKEN must be set before building the image."; exit 1; fi
ENV HF_TOKEN=$HF_TOKEN

ENV HOME=/root
ENV VALIDATION_DIR=$HOME/furiosa-server-validation-tool
WORKDIR $VALIDATION_DIR

ENV OUTPUT_DIR=$HOME/outputs
ENV LOG_DIR=$HOME/logs
RUN mkdir -p "${OUTPUT_DIR}" "${LOG_DIR}"

RUN apt-get update && apt-get install -y \
    sudo \
    bash \
    pciutils \
    python3 \
    python3-pip \
    ca-certificates \
    jq \
    curl \
    gnupg \
    wget \
    vim \
    git \
    && rm -rf /var/lib/apt/lists/*

# Add FuriosaAI repository and install furiosa-toolkit-rngd
RUN curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/cloud.google.gpg && \
    echo "deb [arch=$(dpkg --print-architecture)] http://asia-northeast3-apt.pkg.dev/projects/furiosa-ai $(. /etc/os-release && echo "$VERSION_CODENAME") main" | tee /etc/apt/sources.list.d/furiosa.list && \
    apt-get update && \
    apt-get install -y furiosa-toolkit-rngd=2025.3.2-3 && \
    rm -rf /var/lib/apt/lists/*

# Install furiosa-llm
ENV PIP_EXTRA_INDEX_URL=https://asia-northeast3-python.pkg.dev/furiosa-ai/pypi/simple
RUN pip install furiosa-llm==2025.3.4 'more-itertools<11.0'

COPY entrypoint.sh $VALIDATION_DIR/entrypoint.sh
COPY scripts   $VALIDATION_DIR/scripts/

ENTRYPOINT ["/root/furiosa-server-validation-tool/entrypoint.sh"]
