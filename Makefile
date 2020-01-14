SHELL=/bin/bash

PWD := $(shell pwd)
GIT = $(shell which git)
MAKE = $(shell which make)
RECIPE = dataprep_personnes-dedecees_search
TIMEOUT = 2520
DATAGOUV_API = https://www.data.gouv.fr/api/1/datasets
DATAGOUV_DATASET = fichier-des-personnes-decedees
DATA_DIR = data
# files to sync:
FILES_TO_SYNC=(^|\s)deces-.*.txt(.gz)?($$|\s)
# files to process:
FILES_TO_PROCESS=deces-\d{4}(|-m\d.*).txt.gz
DATAGOUV_CATALOG = ${DATA_DIR}/${DATAGOUV_DATASET}.datagouv.list
S3_BUCKET = ${DATAGOUV_DATASET}
S3_CATALOG = ${DATA_DIR}/${DATAGOUV_DATASET}.s3.list
export ES_BONSAI

dummy               := $(shell touch artifacts)
include ./artifacts

config:
	@echo checking system prerequisites
	@${MAKE} -C backend install-prerequisites install-aws-cli
	@if [ ! -f "/usr/bin/curl" ]; then sudo apt-get install -y curl;fi
	@if [ ! -f "/usr/bin/jq" ]; then sudo apt-get install -y jq;fi
	@echo "prerequisites installed" > config

backend:
	@echo configuring matchID
	@${GIT} clone https://github.com/matchid-project/backend backend
	@cp artifacts backend/artifacts
	@mkdir backend/upload
	@chmod 777 backend/upload
	@curl https://static.data.gouv.fr/resources/fichier-des-personnes-decedees/20191209-182920/deces-1970.txt | gzip > backend/upload/deces-1970.txt.gz
	@cp docker-compose-local.yml backend/docker-compose-local.yml
	@echo "export ES_NODES=1" >> backend/artifacts
	@echo "export PROJECTS=${PWD}/projects" >> backend/artifacts
	@echo "export S3_BUCKET=${S3_BUCKET}" >> backend/artifacts

dev: config backend
	${MAKE} -C backend frontend-build backend elasticsearch frontend

up:
	${MAKE} -C backend backend elasticsearch wait-backend wait-elasticsearch

recipe-bonsai:
	@curl -XDELETE https://${ES_BONSAI}:443/deces
	${MAKE} -C backend recipe-run RECIPE=dataprep_personnes-dedecees_bonsai

recipe-run:
	${MAKE} -C backend recipe-run RECIPE=${RECIPE}

watch-run:
	@timeout=${TIMEOUT} ; ret=1 ; \
		until [ "$$timeout" -le 0 -o "$$ret" -eq "0"  ] ; do \
			f=$$(find backend/log/ -iname '*dataprep_personnes-dedecees_search*' | sort | tail -1);\
		((tail $$f | grep "end of all" > /dev/null) || exit 1) ; \
		ret=$$? ; \
		if [ "$$ret" -ne "0" ] ; then \
			echo "waiting for end of job $$timeout" ; \
			grep wrote $$f |awk 'BEGIN{s=0}{t=$$4;s+=$$12}END{print t " wrote " s}' ;\
			sleep 10 ;\
		fi ; ((timeout--)); done ; exit $$ret
	@find backend/log/ -iname '*dataprep_personnes-dedecees_search*' | sort | tail -1 | xargs tail

backup:
	${MAKE} -C backend elasticsearch-backup

s3-push:
	${MAKE} -C backend elasticsearch-s3-push S3_BUCKET=fichier-des-personnes-decedees

down:
	${MAKE} -C backend backend-stop elasticsearch-stop frontend-stop

clean: down
	sudo rm -rf backend frontend ${DATA_DIR}

test: backend config up recipe-bonsai down
	@echo test ended with succes !!!

all: backend config up recipe-run watch-run down backup s3-push clean
	@echo ended with succes !!!
