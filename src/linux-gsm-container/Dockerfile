# 1. Base image
FROM ubuntu:24.04

# 2. Avoid apt prompts
ENV DEBIAN_FRONTEND=noninteractive

# 3. Build arguments (fallback if not provided via .env)
ARG JAVA_VERSION=21
ARG PUID=998
ARG PGID=998
ARG MC_USER=pmcuser
ARG MC_GROUP=pmcgroup
ARG MC_VOLUME=/minecraft
ARG LGSM_COMMAND=pmcserver
ARG TZ=America/Santiago

# 4. Export runtime environment variables
ENV PUID=${PUID} \
    PGID=${PGID} \
    MC_USER=${MC_USER} \
    MC_GROUP=${MC_GROUP} \
    MC_VOLUME=${MC_VOLUME} \
    LGSM_COMMAND=${LGSM_COMMAND} \
    JAVA_VERSION=${JAVA_VERSION} \
    TZ=${TZ}

# 5. Set timezone
RUN ln -fs /usr/share/zoneinfo/$TZ /etc/localtime && \
    echo $TZ > /etc/timezone

# 6. Install dependencies
RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    sudo curl busybox \
    openjdk-${JAVA_VERSION}-jdk-headless \
    bc binutils bsdmainutils bzip2 cpio distro-info \
    file jq lib32gcc-s1 lib32stdc++6 \
    netcat-openbsd pigz tmux unzip \
    uuid-runtime wget xz-utils \
    libsdl2-2.0-0:i386 python3 && \
    rm -rf /var/lib/apt/lists/*

# 7. Create group and user with UID/GID, set home to MC_VOLUME, temporarily enable sudo
RUN groupadd --gid "${PGID}" "${MC_GROUP}" && \
    useradd --uid "${PUID}" --gid "${PGID}" \
      --shell /bin/sh --home-dir "${MC_VOLUME}" --create-home "${MC_USER}" && \
    echo "${MC_USER} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# 8. Switch to non-root user and set working directory
USER ${MC_USER}
WORKDIR ${MC_VOLUME}

# 9. Download and install LinuxGSM and PaperMC unattended
RUN curl -Lo linuxgsm.sh https://linuxgsm.sh && \
    chmod +x linuxgsm.sh && \
    bash linuxgsm.sh ${LGSM_COMMAND} && \
    ./${LGSM_COMMAND} auto-install

# 10. Switch back to root for backup and sudo cleanup
USER root

# 11. Create initialization tarballs
RUN mkdir -p /backup && \
    tar -C "${MC_VOLUME}" -czf /backup/lgsm.tar.gz lgsm && \
    tar -C "${MC_VOLUME}" -czf /backup/serverfiles.tar.gz serverfiles

# 12. Remove sudo privileges from pmcuser
RUN sed -i "/${MC_USER} ALL=(ALL) NOPASSWD:ALL/d" /etc/sudoers && \
    gpasswd -d ${MC_USER} sudo

# 13. Copy entrypoint script
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# 14. Expose Minecraft and micro api port
EXPOSE 25565
EXPOSE 8080

# 15. Set entrypoint for runtime
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
