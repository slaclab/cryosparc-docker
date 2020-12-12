#CRYOSPARC_VERSION=2.12.4
#CRYOSPARC_VERSION=2.14.2
CRYOSPARC_VERSION=2.15.0
TAG=${CRYOSPARC_VERSION}-8

docker:
	sudo DOCKER_BUILDKIT=1 docker build \
		--build-arg CRYOSPARC_VERSION=${CRYOSPARC_VERSION} \
		--progress=plain \
		--secret id=cryosparc_license_id,src=./license_id.txt \
		. \
		-t slaclab/cryosparc-docker:${TAG}
	sudo docker push slaclab/cryosparc-docker:${TAG}

desktop:
	sudo COMPOSE_DOCKER_CLI_BUILD=1 DOCKER_BUILDKIT=1 docker build \
		--build-arg CRYOSPARC_VERSION=${CRYOSPARC_VERSION} \
		--progress=plain \
		--secret id=cryosparc_license_id,src=./license_id.txt \
		. -f Dockerfile.desktop \
	-t slaclab/cryosparc-desktop:${TAG}
	sudo docker push slaclab/cryosparc-desktop:${TAG}

desktop-singularity:
	singularity pull -F /sdf/group/cryoem/sw/images/cryosparc/${CRYOSPARC_VERSION}-desktop/cryosparc-desktop_${CRYOSPARC_VERSION}.sif2 docker://slaclab/cryosparc-desktop:${TAG}
