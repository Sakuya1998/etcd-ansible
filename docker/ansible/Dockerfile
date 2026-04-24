FROM python:3.12-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    openssh-client sshpass git bash ca-certificates \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# ansible-core（在容器内跑 playbook）
RUN pip install --no-cache-dir ansible-core==2.17.* jmespath \
  && ansible-galaxy collection install community.crypto

WORKDIR /repo

