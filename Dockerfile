# syntax=docker/dockerfile:experimental
FROM nvidia/cuda:11.4.3-devel-ubuntu20.04

ENV DEBIAN_FRONTEND noninteractive

# munge and slurm stuff
ARG MUNGEUSER=16952
ARG MUNGEGROUP=1034
ARG SLURMUSER=16924
ARG SLURMGROUP=1034
RUN groupadd -f -g $SLURMGROUP slurm \
    && useradd  -m -c "SLURM workload manager" -d /var/lib/slurm -u $SLURMUSER -g slurm  -s /bin/bash slurm

RUN apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 2930ADAE8CAF5059EE73BB4B58712A2291FA4AD5 2F59B5F99B1BE0B4\
  && apt-get update \
  && apt-get install -y --no-install-recommends \
    apt-utils \
    zip unzip \
    python \
    python3 \
    python3-dev \
    python3-setuptools \
    python3-pip \
    libtiff5 \
    netbase \
    ed \
    curl \
    iputils-ping \
    sudo \
    net-tools \
    openssh-server \
    jq \
    munge \
    ca-certificates \
    gnupg \
  && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /usr/share/keyrings/nodesource.gpg \
  && echo "deb [ signed-by=/usr/share/keyrings/nodesource.gpg ] https://deb.nodesource.com/node_21.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list \
  && apt-get update \
  && apt-get install -y nodejs \
  && curl -fsSL https://repo.mongodb.org/apt/ubuntu/dists/focal/mongodb-org/6.0/Release.gpg | tee /usr/share/keyrings/mongodb.gpg \
  && echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/key-file.gpg ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/6.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-6.0.list \
  && rm -rf /var/lib/apt/lists/* \
  && ln -s /usr/lib/x86_64-linux-gnu/libtiff.so.5 /usr/lib/x86_64-linux-gnu/libtiff.so.3

RUN groupmod -o -g $MUNGEGROUP munge \
    && usermod -c "MUNGE Uid 'N' Gid Emporium" -d /var/lib/munge -u $MUNGEUSER -g munge  -s /sbin/nologin munge \
    && chown -R munge:$MUNGEGROUP /etc/munge 

ENV CRYOSPARC_ROOT_DIR /app
RUN mkdir -p ${CRYOSPARC_ROOT_DIR}
WORKDIR ${CRYOSPARC_ROOT_DIR}

ARG CRYOSPARC_VERSION
ENV CRYOSPARC_VERSION=${CRYOSPARC_VERSION}

# install master
ENV CRYOSPARC_MASTER_DIR ${CRYOSPARC_ROOT_DIR}/cryosparc_master
RUN --mount=type=secret,id=cryosparc_license_id \
  curl -L https://get.cryosparc.com/download/master-v${CRYOSPARC_VERSION}/$(cat /run/secrets/cryosparc_license_id) | tar -xz \
	&& cd ${CRYOSPARC_MASTER_DIR} \
  && sed -i '/^echo "# Other" >> config.sh$/a echo \"CRYOSPARC_FORCE_USER=true\" >> config.sh' ./install.sh \
  && bash ./install.sh --license "$(cat /run/secrets/cryosparc_license_id)" --yes --allowroot \
  && sed -i 's/^export CRYOSPARC_LICENSE_ID=.*$/export CRYOSPARC_LICENSE_ID=TBD/g' ${CRYOSPARC_MASTER_DIR}/config.sh 

ARG CRYOSPARC_PATCH
ENV CRYOSPARC_PATCH=${CRYOSPARC_PATCH}

# update patches
RUN if [ ! -z "${CRYOSPARC_PATCH}" ]; then curl -L https://get.cryosparc.com/patch_get/v${CRYOSPARC_VERSION}+${CRYOSPARC_PATCH}/master -o ${CRYOSPARC_ROOT_DIR}/cryosparc_master_patch.tar.gz \
  && tar -vxzf ${CRYOSPARC_ROOT_DIR}/cryosparc_master_patch.tar.gz --overwrite --strip-components=1 --directory=${CRYOSPARC_MASTER_DIR} \
  && rm -f ${CRYOSPARC_ROOT_DIR}/cryosparc_master_patch.tar.gz; fi

# patches
RUN sed -i 's:    disk_has_space=.*:    disk_has_space="true":g'  ${CRYOSPARC_MASTER_DIR}/bin/cryosparcm

# install worker
ENV CRYOSPARC_WORKER_DIR ${CRYOSPARC_ROOT_DIR}/cryosparc_worker
RUN --mount=type=secret,id=cryosparc_license_id \
  curl -L https://get.cryosparc.com/download/worker-v${CRYOSPARC_VERSION}/$(cat /run/secrets/cryosparc_license_id) | tar -xz \
  && cd ${CRYOSPARC_WORKER_DIR} \
  && bash ./install.sh --license "$(cat /run/secrets/cryosparc_license_id)" --yes --cudapath /usr/local/cuda \
  && sed -i '/^echo "# Other" >> config.sh$/a echo \"CRYOSPARC_FORCE_USER=true\" >> config.sh' ./install.sh \
  && sed -i 's/^export CRYOSPARC_LICENSE_ID=.*$/export CRYOSPARC_LICENSE_ID=TBD/g' ${CRYOSPARC_WORKER_DIR}/config.sh 

# update patches
RUN if [ ! -z "${CRYOSPARC_PATCH}" ]; then curl -L https://get.cryosparc.com/patch_get/v${CRYOSPARC_VERSION}+${CRYOSPARC_PATCH}/worker -o ${CRYOSPARC_ROOT_DIR}/cryosparc_worker_patch.tar.gz \
  && tar -vxzf ${CRYOSPARC_ROOT_DIR}/cryosparc_worker_patch.tar.gz --overwrite --strip-components=1 --directory=${CRYOSPARC_WORKER_DIR} \
  && rm -f ${CRYOSPARC_ROOT_DIR}/cryosparc_worker_patch.tar.gz; fi

# install cryosparc live
ARG CRYOSPARC_LIVE
RUN --mount=type=secret,id=cryosparc_license_id \
  if [ ! -z $CRYOSPARC_LIVE ]; then cd ${CRYOSPARC_MASTER_DIR} \
    curl -L "https://get.cryosparc.com/download/master-${CRYOSPARC_LIVE}/$(cat /run/secrets/cryosparc_license_id)" | tar -xz --overwrite --strip-components=1 --directory . \
    && ${CRYOSPARC_MASTER_DIR}/bin/cryosparcm deps \
    && sed -i 's/^export CRYOSPARC_LICENSE_ID=.*$/export CRYOSPARC_LICENSE_ID=TBD/g' ${CRYOSPARC_MASTER_DIR}/config.sh; \
  fi
RUN --mount=type=secret,id=cryosparc_license_id \
  if [ ! -z $CRYOSPARC_LIVE ]; then cd ${CRYOSPARC_WORKER_DIR} \
    curl -L "https://get.cryosparc.com/download/worker-${CRYOSPARC_LIVE}/$(cat /run/secrets/cryosparc_license_id)" | tar -xz --overwrite --strip-components=1 --directory . \
    && ${CRYOSPARC_WORKER_DIR}/bin/cryosparcw deps \
    && sed -i 's/^export CRYOSPARC_LICENSE_ID=.*$/export CRYOSPARC_LICENSE_ID=TBD/g' ${CRYOSPARC_WORKER_DIR}/config.sh; \
  fi

####
## install motioncor
####
ARG MOTIONCOR2_VERSION=1.6.4
ENV MOTIONCOR2_VERSION=${MOTIONCOR2_VERSION}
RUN cd /usr/local/bin \
  && curl -L 'https://drive.google.com/uc?export=download&id=1hskY_AbXVgrl_BUIjWokDNLZK0c1FLxF' > MotionCor2_${MOTIONCOR2_VERSION}.zip \
  && unzip MotionCor2_${MOTIONCOR2_VERSION}.zip \
  && rm -f MotionCor2_${MOTIONCOR2_VERSION}.zip \
  && ln -sf MotionCor2_${MOTIONCOR2_VERSION}-Cuda100 MotionCor2

COPY entrypoint.bash /entrypoint.bash
COPY cryosparc.sh /cryosparc.sh
COPY cryosparc-server.sh ${CRYOSPARC_MASTER_DIR}/bin/cryosparc-server.sh

ADD slurm /app/slurm

EXPOSE 39000
EXPOSE 39001
EXPOSE 39002
EXPOSE 39003
EXPOSE 39004
EXPOSE 39006

ENTRYPOINT /entrypoint.bash
