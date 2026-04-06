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

# git-delta, glow, and GitHub CLI (not in Ubuntu apt repos)
RUN ARCH=$(dpkg --print-architecture) \
  && DELTA_VERSION=0.18.2 \
  && if [ "$ARCH" = "arm64" ]; then DELTA_ARCH=aarch64; GLOW_ARCH=arm64; GH_ARCH=arm64; else DELTA_ARCH=x86_64; GLOW_ARCH=x86_64; GH_ARCH=amd64; fi \
  && curl -fsSL "https://github.com/dandavison/delta/releases/download/${DELTA_VERSION}/delta-${DELTA_VERSION}-${DELTA_ARCH}-unknown-linux-gnu.tar.gz" \
    | tar xz --strip-components=1 -C /usr/local/bin "delta-${DELTA_VERSION}-${DELTA_ARCH}-unknown-linux-gnu/delta" \
  && curl -fsSL "https://github.com/charmbracelet/glow/releases/download/v2.0.0/glow_2.0.0_Linux_${GLOW_ARCH}.tar.gz" \
    | tar xz --strip-components=1 -C /usr/local/bin "glow_2.0.0_Linux_${GLOW_ARCH}/glow" \
  && GH_VERSION=2.89.0 \
  && curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${GH_ARCH}.tar.gz" \
    | tar xz --strip-components=1 -C /usr/local

# Node.js 22.x via NodeSource
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*

# Bun 1.2.5
ENV BUN_INSTALL=/usr/local/bun
RUN curl -fsSL https://bun.sh/install | bash -s -- "bun-v1.2.5"
ENV PATH="/usr/local/bun/bin:${PATH}"

# uv package manager (pinned version, installs directly to /usr/local/bin)
ENV UV_INSTALL_DIR=/usr/local/bin
RUN curl -LsSf https://astral.sh/uv/0.6.14/install.sh | sh

# OpenCode (installs to /root/.opencode/bin/, copy to shared path)
RUN curl -fsSL https://opencode.ai/install | bash \
  && cp /root/.opencode/bin/opencode /usr/local/bin/opencode

# Create developer user (reuse ubuntu user if exists, else create)
RUN if id ubuntu &>/dev/null; then \
        usermod -l developer -d /home/developer -m ubuntu && \
        groupmod -n developer ubuntu; \
    else \
        useradd -m -s /bin/bash developer; \
    fi && \
    echo "developer ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/developer && \
    chmod 0440 /etc/sudoers.d/developer

# Switch to developer user
USER developer
WORKDIR /home/developer

# Install Python 3.12 via uv
RUN uv python install 3.12

# Set PATH for developer
ENV PATH="/home/developer/.local/bin:/usr/local/bun/bin:/usr/local/bin:${PATH}"

COPY --chown=developer:developer entrypoint.sh /home/developer/entrypoint.sh
RUN chmod 755 /home/developer/entrypoint.sh

WORKDIR /workspace

ENTRYPOINT ["/home/developer/entrypoint.sh"]
CMD ["bash"]
