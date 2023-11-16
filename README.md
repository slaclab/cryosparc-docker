# docker image for cryosparc v2

You first need to obtain a license for cryosparc via https://cryosparc.com/download/ and cat it into a location that so that the docker build process can pick it up:

```
export CRYOSPARC_LICENSE_ID=<BLAH>
make license
```

All this really does is to put it into a text file under .secret.

Then to actually build the image:

```
make build
```
    
You can change the version to be installed via environment variables, eg to install

```
CRYOSPARC_VERSION=4.4.0 CRYOSPARC_PATCH=231114 make build
```


Developer
===
    
run (for testing) via

    docker run -e CRYOSPARC_LICENSE_ID=${CRYOSPARC_LICENSE_ID} \
        -e JUPYTERHUB_USER=ytl -e EXTERNAL_UID=7017 \
        -e EXTERNAL_GROUPS=sf:1051,cryo-data:3591,bd:1124 \
        -e HOMEDIRS=/gpfs/slac/cryo/fs1/u/ \
        -v /gpfs/slac/cryo/fs1/u/ytl/cryosparc-v2/:/gpfs/slac/cryo/fs1/u/ \
        -v /gpfs/slac/cryo/fs1/exp/:/gpfs/slac/cryo/fs1/exp/ \
        -v /scratch:/scratch \
        -p 39000:39000 -p 39001:39001 -p 39002:39002 -p 39003:39003 -p 39004:39004 \
        slaclab/cryosparc-docker:2.2.0

notes

- to enable access to file storage, the container will drop privs to that defined by JUPYTERHUB_USER, EXTERNAL_UID and EXTERNAL_GROUPS.

