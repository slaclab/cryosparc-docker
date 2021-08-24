CRYOSPARC_VERSION ?= 3.2.0
CRYOSPARC_PATCH ?= 210817
CRYOSPARC_RELEASE ?= 0
CRYOSPARC_FULL_VERSION ?= ${CRYOSPARC_VERSION}-${CRYOSPARC_PATCH}
TAG ?= ${CRYOSPARC_FULL_VERSION}-${CRYOSPARC_RELEASE}

#docker:
#	sudo DOCKER_BUILDKIT=1 docker build \
#		--build-arg CRYOSPARC_VERSION=${CRYOSPARC_VERSION} \
#		--progress=plain \
#		--secret id=cryosparc_license_id,src=./license_id.txt \
#		. \
#		-t slaclab/cryosparc-docker:${TAG}
#	sudo docker push slaclab/cryosparc-docker:${TAG}

desktop:
	sudo COMPOSE_DOCKER_CLI_BUILD=1 DOCKER_BUILDKIT=1 docker build \
		--build-arg CRYOSPARC_VERSION=${CRYOSPARC_VERSION} \
		--build-arg CRYOSPARC_PATCH=${CRYOSPARC_PATCH} \
		--progress=plain \
		--secret id=cryosparc_license_id,src=./license_id.txt \
		. -f Dockerfile.desktop \
	-t slaclab/cryosparc-desktop:${TAG}
	echo sudo docker push slaclab/cryosparc-desktop:${TAG}

desktop-singularity:
	mkdir -p /sdf/group/cryoem/sw/images/cryosparc/${CRYOSPARC_FULL_VERSION}-desktop/
	#singularity pull -F /sdf/group/cryoem/sw/images/cryosparc/${CRYOSPARC_VERSION}-desktop/cryosparc-desktop_${CRYOSPARC_VERSION}.sif oras://docker-registry.slac.stanford.edu/slaclab/cryosparc-desktop:${TAG}
	singularity pull -F /sdf/group/cryoem/sw/images/cryosparc/${CRYOSPARC_FULL_VERSION}-desktop/cryosparc-desktop_${CRYOSPARC_FULL_VERSION}.sif docker://slaclab/cryosparc-desktop:${TAG}
