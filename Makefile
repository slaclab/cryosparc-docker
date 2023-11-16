CRYOSPARC_VERSION ?= 4.4.0
CRYOSPARC_PATCH ?= 231114
CRYOSPARC_RELEASE ?= 0

CONTAINER_RUNTIME ?= docker
IMAGE ?= slaclab/cryosparc-desktop

tag:
ifeq ($(CRYOSPARC_PATCH),)
CRYOSPARC_FULL_VERSION = $(CRYOSPARC_VERSION)
else
CRYOSPARC_FULL_VERSION = $(CRYOSPARC_VERSION)+$(CRYOSPARC_PATCH)
endif
TAG = $(subst +,-,$(CRYOSPARC_FULL_VERSION)-$(CRYOSPARC_RELEASE))
CRYOSPARC_IMAGE_INSTALL_DIR = /sdf/group/cryoem/sw/images/cryosparc/$(CRYOSPARC_FULL_VERSION)-desktop

echo_tag: tag
	echo "TAG=$(TAG)"

license:
	mkdir .secret
	echo ${CRYOSPARC_LICENSE_ID} > .secret/license_id.txt

build: tag
	COMPOSE_DOCKER_CLI_BUILD=1 DOCKER_BUILDKIT=1 $(CONTAINER_RUNTIME) build \
		--build-arg CRYOSPARC_VERSION=${CRYOSPARC_VERSION} \
		--build-arg CRYOSPARC_PATCH=${CRYOSPARC_PATCH} \
		--progress=plain \
		--secret id=cryosparc_license_id,src=.secret/license_id.txt \
		. -f Dockerfile.desktop \
	-t $(IMAGE):${TAG}

push: build
	$(CONTAINER_RUNTIME) push $(IMAGE):${TAG}

apptainer: tag
	mkdir -p ${CRYOSPARC_IMAGE_INSTALL_DIR}
	echo apptainer pull -F ${CRYOSPARC_IMAGE_INSTALL_DIR}/cryosparc-desktop@${CRYOSPARC_FULL_VERSION}.sif docker://slaclab/cryosparc-desktop:${TAG}

all: build push apptainer
 
