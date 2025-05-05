CRYOSPARC_VERSION ?= 4.6.2
CRYOSPARC_PATCH ?= 
CRYOSPARC_RELEASE ?= 0
CONTAINER_RUNTIME ?= podman
IMAGE ?= slaclab/cryosparc-desktop

tag:
ifeq ($(CRYOSPARC_PATCH),)
CRYOSPARC_FULL_VERSION = $(CRYOSPARC_VERSION)
else
CRYOSPARC_FULL_VERSION = $(CRYOSPARC_VERSION)+$(CRYOSPARC_PATCH)
endif
TAG = $(subst +,-,$(CRYOSPARC_FULL_VERSION)-$(CRYOSPARC_RELEASE))
CRYOSPARC_IMAGE_INSTALL_DIR = /sdf/group/cryoem/sw/images/cryosparc/$(TAG)

echo_tag: tag
	echo "TAG=$(TAG)"

license:
	mkdir -p etc/.secrets
ifeq ($(CRYOSPARC_LICENSE_ID),)
	echo "CRYOSPARC_LICENSE_ID cannot be blank"
else
	@echo ${CRYOSPARC_LICENSE_ID} > etc/.secrets/cryosparc_license_id.txt
endif
	
ifeq ($(MOTIONCOR2_LICENSE_ID),)
	echo "MOTIONCOR2_LICENSE_ID cannot be blank"
else
	@echo ${MOTIONCOR2_LICENSE_ID} > etc/.secrets/motioncor2_license_id.txt
endif

clean-license:
	rm -rf etc/.secrets

build: tag
	COMPOSE_DOCKER_CLI_BUILD=1 DOCKER_BUILDKIT=1 $(CONTAINER_RUNTIME) build \
		--build-arg CRYOSPARC_VERSION=${CRYOSPARC_VERSION} \
		--build-arg CRYOSPARC_PATCH=${CRYOSPARC_PATCH} \
		--progress=plain \
		--secret id=cryosparc_license_id,src=etc/.secrets/cryosparc_license_id.txt \
	    --secret id=motioncor2_license_id,src=etc/.secrets/motioncor2_license_id.txt \
		. -f Dockerfile.desktop \
	-t $(IMAGE):${TAG}

push:
	$(CONTAINER_RUNTIME) push $(IMAGE):${TAG}

apptainer: tag
	mkdir -p ${CRYOSPARC_IMAGE_INSTALL_DIR}
	apptainer pull -F ${CRYOSPARC_IMAGE_INSTALL_DIR}/cryosparc-desktop@${TAG}.sif docker://slaclab/cryosparc-desktop:${TAG}

all: build push apptainer
 
