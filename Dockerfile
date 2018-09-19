FROM nvidia/cuda:9.1-devel-ubuntu16.04

ARG CRYOSPARC_LICENSE_ID

RUN apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 2930ADAE8CAF5059EE73BB4B58712A2291FA4AD5 \
  && echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu xenial/mongodb-org/3.6 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-3.6.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
    python \
    libtiff5 \
    netbase \
    curl \
    iputils-ping \
    sudo \
    net-tools \
    openssh-server \
  && rm -rf /var/lib/apt/lists/*
RUN ln -s /usr/lib/x86_64-linux-gnu/libtiff.so.5 /usr/lib/x86_64-linux-gnu/libtiff.so.3

ENV CRYOSPARC_ROOT_DIR /app
RUN mkdir -p ${CRYOSPARC_ROOT_DIR}
WORKDIR ${CRYOSPARC_ROOT_DIR}

# download latest
RUN curl -L https://get.cryosparc.com/download/master-latest/${CRYOSPARC_LICENSE_ID} | tar -xz
RUN curl -L https://get.cryosparc.com/download/worker-latest/${CRYOSPARC_LICENSE_ID} | tar -xz

# install master
ENV CRYOSPARC_MASTER_DIR ${CRYOSPARC_ROOT_DIR}/cryosparc2_master
RUN cd ${CRYOSPARC_MASTER_DIR} && \
  bash ./install.sh --license ${CRYOSPARC_LICENSE_ID} --yes --allowroot && \
  sed -i 's/^export CRYOSPARC_LICENSE_ID=.*$/export CRYOSPARC_LICENSE_ID=TBD/g' ${CRYOSPARC_MASTER_DIR}/config.sh

# install worker
ENV CRYOSPARC_WORKER_DIR ${CRYOSPARC_ROOT_DIR}/cryosparc2_worker
RUN cd ${CRYOSPARC_WORKER_DIR} && \
  bash ./install.sh --license ${CRYOSPARC_LICENSE_ID} --yes --cudapath /usr/local/cuda && \
  sed -i 's/^export CRYOSPARC_LICENSE_ID=.*$/export CRYOSPARC_LICENSE_ID=TBD/g' ${CRYOSPARC_WORKER_DIR}/config.sh

COPY entrypoint.bash /entrypoint.bash
COPY cryosparc.sh /cryosparc.sh

EXPOSE 39000
EXPOSE 39001
EXPOSE 39002
EXPOSE 39003
EXPOSE 39004

ENTRYPOINT /entrypoint.bash