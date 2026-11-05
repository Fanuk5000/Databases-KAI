FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Install base tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg \
    locales \
    lsb-release \
    nano \
    procps \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# Configure locales
RUN locale-gen en_US.UTF-8 uk_UA.UTF-8 C.UTF-8 \
    && update-locale LANG=C.UTF-8 LC_ALL=C.UTF-8

ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# Add official PostgreSQL PGDG repository
RUN install -d /etc/apt/keyrings \
    && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/keyrings/postgresql.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list

# Install PostgreSQL 18 (fallback to 17 if 18 not yet packaged for Noble)
RUN apt-get update && \
    (apt-get install -y --no-install-recommends postgresql-18 postgresql-client-18 || \
     apt-get install -y --no-install-recommends postgresql-17 postgresql-client-17) \
    && rm -rf /var/lib/apt/lists/*

# Configure passwordless sudo for postgres user
RUN echo "postgres ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/postgres \
    && chmod 0440 /etc/sudoers.d/postgres

# Set default PATH for all interactive shells
RUN echo 'export PATH=/usr/lib/postgresql/18/bin:/usr/lib/postgresql/17/bin:$PATH' > /etc/profile.d/postgresql.sh \
    && echo 'export PATH=/usr/lib/postgresql/18/bin:/usr/lib/postgresql/17/bin:$PATH' >> /etc/bash.bashrc \
    && echo 'export PATH=/usr/lib/postgresql/18/bin:/usr/lib/postgresql/17/bin:$PATH' >> /var/lib/postgresql/.bashrc

# Expose ports: 55440 (main), 55441 (restore1)
# EXPOSE 55440 55441 # For Dbviewer and other stuff

WORKDIR /root

CMD ["/bin/bash"]
