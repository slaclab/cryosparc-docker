#CRYOSPARC_VERSION=2.12.4
#CRYOSPARC_VERSION=2.14.2
CRYOSPARC_VERSION=2.15.0
TAG=${CRYOSPARC_VERSION}-6


docker:
	sudo DOCKER_BUILDKIT=1 docker build \
		--build-arg CRYOSPARC_VERSION=${CRYOSPARC_VERSION} \
		--progress=plain \
		--secret id=cryosparc_license_id,src=./license_id.txt \
		. \
		-t slaclab/cryosparc-docker:${TAG}
	sudo docker push slaclab/cryosparc-docker:${TAG}

