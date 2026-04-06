FROM ubuntu:24.04

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive

# OS packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    wget \
    jq \
    ripgrep \
    fd-find \
    fzf \
    tree \
    htop \
    tmux \
    openssh-client \
    ca-certificates \
    build-essential \
    zip \
    unzip \
    sudo \
    bat \
    && rm -rf /var/lib/apt/lists/*

# Symlinks for fd and bat
RUN ln -sf "$(which fdfind)" /usr/local/bin/fd \
    && ln -sf "$(which batcat)" /usr/local/bin/bat

# Detect architecture for multi-arch installs
ARG TARGETARCH
RUN ARCH=$(dpkg --print-architecture) && \
    # git-delta 0.18.2
    if [ "$ARCH" = "arm64" ]; then \
        DELTA_ARCH="aarch64"; \
    else \
        DELTA_ARCH="x86_64"; \
    fi && \
    curl -fsSL "https://github.com/dandavison/delta/releases/download/0.18.2/delta-0.18.2-${DELTA_ARCH}-unknown-linux-gnu.tar.gz" \
        | tar xz -C /tmp && \
    mv /tmp/delta-0.18.2-${DELTA_ARCH}-unknown-linux-gnu/delta /usr/local/bin/delta && \
    rm -rf /tmp/delta-* && \
    # glow 2.0.0
    if [ "$ARCH" = "arm64" ]; then \
        GLOW_ARCH="arm64"; \
    else \
        GLOW_ARCH="x86_64"; \
    fi && \
    curl -fsSL "https://github.com/charmbracelet/glow/releases/download/v2.0.0/glow_2.0.0_Linux_${GLOW_ARCH}.tar.gz" \
        | tar xz -C /tmp && \
    mv /tmp/glow /usr/local/bin/glow && \
    rm -rf /tmp/glow* && \
    # GitHub CLI 2.74.0
    if [ "$ARCH" = "arm64" ]; then \
        GH_ARCH="arm64"; \
    else \
        GH_ARCH="amd64"; \
    fi && \
    curl -fsSL "https://github.com/cli/cli/releases/download/v2.74.0/gh_2.74.0_linux_${GH_ARCH}.tar.gz" \
        | tar xz -C /tmp && \
    mv /tmp/gh_2.74.0_linux_${GH_ARCH}/bin/gh /usr/local/bin/gh && \
    rm -rf /tmp/gh_*

# Node.js 22.x via NodeSource
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*

# Bun 1.2.5
ENV BUN_INSTALL=/usr/local/bun
RUN curl -fsSL https://bun.sh/install | bash -s -- "bun-v1.2.5"
ENV PATH="/usr/local/bun/bin:${PATH}"

# uv package manager
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:${PATH}"

# OpenCode
RUN curl -fsSL https://opencode.ai/install | bash

# Create developer user (reuse ubuntu user if exists, else create)
RUN if id ubuntu &>/dev/null; then \
        usermod -l developer -d /home/developer -m ubuntu && \
        groupmod -n developer ubuntu; \
    else \
        useradd -m -s /bin/bash developer; \
    fi && \
    echo "developer ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/developer && \
    chmod 0440 /etc/sudoers.d/developer

# Copy uv and opencode binaries to developer-accessible locations
RUN cp -r /root/.local/bin/* /usr/local/bin/ 2>/dev/null || true && \
    cp -r /root/.opencode/bin/* /usr/local/bin/ 2>/dev/null || true

# Switch to developer user
USER developer
WORKDIR /home/developer

# Install Python 3.12 via uv
RUN uv python install 3.12

# Set PATH for developer
ENV PATH="/home/developer/.local/bin:/home/developer/.opencode/bin:/usr/local/bun/bin:/usr/local/bin:${PATH}"

COPY --chown=developer:developer entrypoint.sh /home/developer/entrypoint.sh
RUN chmod 755 /home/developer/entrypoint.sh

WORKDIR /workspace

ENTRYPOINT ["/home/developer/entrypoint.sh"]
CMD ["bash"]
