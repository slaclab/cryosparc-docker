CRYOSPARC_VERSION ?= 4.5.3
CRYOSPARC_PATCH ?= 
CRYOSPARC_RELEASE ?= 0

CONTAINER_RUNTIME ?= docker
IMAGE ?= slaclab/cryosparc-desktop

tag:
ifeq ($(CRYOSPARC_PATCH),)
CRYOSPARC_FULL_VERSION = $(CRYOSPARC_VERSION)
else
CRYOSPARC_FULL_VERSION = $(CRYOSPARC_VERSION)+$(CRYOSPARC_PATCH)
endif
ifeq ($(CRYOSPARC_RELEASE),)
TAG = $(subst +,-,$(CRYOSPARC_FULL_VERSION))
else
TAG = $(subst +,-,$(CRYOSPARC_FULL_VERSION)-$(CRYOSPARC_RELEASE))
endif
CRYOSPARC_IMAGE_INSTALL_DIR = /sdf/group/cryoem/sw/images/cryosparc/$(CRYOSPARC_FULL_VERSION)-desktop

echo_tag: tag
	echo "TAG=$(TAG)"

license:
	mkdir -p etc/.secrets
	echo ${CRYOSPARC_LICENSE_ID} > etc/.secrets/cryosparc_license_id.txt
        echo ${MOTIONCOR2_LICENSE_ID} > etc/.secrets/motioncor2_license_id.txt

build: tag
	COMPOSE_DOCKER_CLI_BUILD=1 DOCKER_BUILDKIT=1 $(CONTAINER_RUNTIME) build \
		--build-arg CRYOSPARC_VERSION=${CRYOSPARC_VERSION} \
		--build-arg CRYOSPARC_PATCH=${CRYOSPARC_PATCH} \
		--platform linux/amd64 \
		--progress=plain \
		--secret id=cryosparc_license_id,src=etc/.secrets/cryosparc_license_id.txt \
		--secret id=motioncor2_license_id,src=etc/.secrets/motioncor2_license_id.txt \
		. -f Dockerfile.desktop \
	-t $(IMAGE):${TAG}

push: build
	$(CONTAINER_RUNTIME) push $(IMAGE):${TAG}

apptainer: tag
	mkdir -p ${CRYOSPARC_IMAGE_INSTALL_DIR}
	echo apptainer pull -F ${CRYOSPARC_IMAGE_INSTALL_DIR}/cryosparc-desktop@${CRYOSPARC_FULL_VERSION}.sif docker://slaclab/cryosparc-desktop:${TAG}

all: build push apptainer
 
