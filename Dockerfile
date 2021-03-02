# syntax=docker/dockerfile:experimental
FROM nvidia/cuda:10.0-devel-ubuntu16.04

ENV DEBIAN_FRONTEND noninteractive

# munge and slurm stuff
ARG MUNGEUSER=16952
ARG MUNGEGROUP=1034
ARG SLURMUSER=16924
ARG SLURMGROUP=1034
RUN groupadd -f -g $SLURMGROUP slurm \
    && useradd  -m -c "SLURM workload manager" -d /var/lib/slurm -u $SLURMUSER -g slurm  -s /bin/bash slurm

RUN apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 2930ADAE8CAF5059EE73BB4B58712A2291FA4AD5 \
  && echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu xenial/mongodb-org/3.6 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-3.6.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
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
  && curl -sL https://deb.nodesource.com/setup_6.x | bash - \
  && apt-get install -y nodejs \
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
  && bash ./install.sh --license "$(cat /run/secrets/cryosparc_license_id)" --yes --allowroot \
  && sed -i 's/^export CRYOSPARC_LICENSE_ID=.*$/export CRYOSPARC_LICENSE_ID=TBD/g' ${CRYOSPARC_MASTER_DIR}/config.sh 

# patches
RUN sed -i 's:    disk_has_space=.*:    disk_has_space="true":g'  ${CRYOSPARC_MASTER_DIR}/bin/cryosparcm

# install worker
ENV CRYOSPARC_WORKER_DIR ${CRYOSPARC_ROOT_DIR}/cryosparc_worker
RUN --mount=type=secret,id=cryosparc_license_id \
  curl -L https://get.cryosparc.com/download/worker-v${CRYOSPARC_VERSION}/$(cat /run/secrets/cryosparc_license_id) | tar -xz \
  && cd ${CRYOSPARC_WORKER_DIR} \
  && bash ./install.sh --license "$(cat /run/secrets/cryosparc_license_id)" --yes --cudapath /usr/local/cuda \
  && sed -i 's/^export CRYOSPARC_LICENSE_ID=.*$/export CRYOSPARC_LICENSE_ID=TBD/g' ${CRYOSPARC_WORKER_DIR}/config.sh 

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
ARG MOTIONCOR2_VERSION=1.2.3
ENV MOTIONCOR2_VERSION=${MOTIONCOR2_VERSION}
RUN cd /usr/local/bin \
  && curl -L 'https://drive.google.com/uc?export=download&id=17dOr87lhhxGhg6xQYr4f8eo0OEo-GdUI' > MotionCor2_${MOTIONCOR2_VERSION}.zip \
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

# stupid patch
#RUN if [ "${CRYOSPARC_VERSION}" = "2.14.2" ]; then curl -L 'https://structura-assets.s3.amazonaws.com/select2d_v2.14_index_error_bugfix/run.py' > ${CRYOSPARC_MASTER_DIR}/cryosparc2_compute/jobs/select2D/run.py; fi

ENTRYPOINT /entrypoint.bash
