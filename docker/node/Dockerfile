FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# systemd + sshd + python（给 ansible 用）+ sudo（become 用）
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    systemd systemd-sysv dbus \
    openssh-server sudo \
    python3 python3-apt ca-certificates curl iproute2 \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# sshd
RUN mkdir -p /var/run/sshd \
  && sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config \
  && sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config

# ansible 用户（密码：ansible）+ sudo 免密
RUN useradd -m -s /bin/bash ansible \
  && echo "ansible:ansible" | chpasswd \
  && usermod -aG sudo ansible \
  && printf "ansible ALL=(ALL) NOPASSWD:ALL\n" > /etc/sudoers.d/ansible \
  && chmod 0440 /etc/sudoers.d/ansible

# 启用 ssh 服务（systemd）
RUN systemctl enable ssh

VOLUME ["/sys/fs/cgroup"]

STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]

