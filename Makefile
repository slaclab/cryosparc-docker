CRYOSPARC_VERSION ?= 4.0.3
CRYOSPARC_PATCH ?= 
CRYOSPARC_RELEASE ?= 0
#CRYOSPARC_FULL_VERSION ?= ${CRYOSPARC_VERSION}-${CRYOSPARC_PATCH}
#TAG ?= ${CRYOSPARC_FULL_VERSION}-${CRYOSPARC_RELEASE}

#docker:
#	sudo DOCKER_BUILDKIT=1 docker build \
#		--build-arg CRYOSPARC_VERSION=${CRYOSPARC_VERSION} \
#		--progress=plain \
#		--secret id=cryosparc_license_id,src=./license_id.txt \
#		. \
#		-t slaclab/cryosparc-docker:${TAG}
#	sudo docker push slaclab/cryosparc-docker:${TAG}

tag:
ifeq ($(CRYOSPARC_PATCH),)
CRYOSPARC_FULL_VERSION = $(CRYOSPARC_VERSION)
else
CRYOSPARC_FULL_VERSION = $(CRYOSPARC_VERSION)+$(CRYOSPARC_PATCH)
endif
TAG = $(CRYOSPARC_FULL_VERSION)-$(CRYOSPARC_RELEASE)
CRYOSPARC_IMAGE_INSTALL_DIR=/sdf/group/cryoem/sw/images/cryosparc/${CRYSPARC_FULL_VERSION}-desktop

echo_tag: tag
	echo "TAG=$(TAG)"

desktop: tag
	sudo COMPOSE_DOCKER_CLI_BUILD=1 DOCKER_BUILDKIT=1 docker build \
		--build-arg CRYOSPARC_VERSION=${CRYOSPARC_VERSION} \
		--build-arg CRYOSPARC_PATCH=${CRYOSPARC_PATCH} \
		--progress=plain \
		--secret id=cryosparc_license_id,src=./license_id.txt \
		. -f Dockerfile.desktop \
	-t slaclab/cryosparc-desktop:${TAG}
	sudo docker push slaclab/cryosparc-desktop:${TAG}

desktop-singularity: tag
	mkdir -p ${CRYOSPARC_IMAGE_INSTALL_DIR}
	singularity pull -F ${CRYOSPARC_IMAGE_INSTALL_DIR}/cryosparc-desktop@${CRYOSPARC_FULL_VERSION}.sif docker://slaclab/cryosparc-desktop:${TAG}
