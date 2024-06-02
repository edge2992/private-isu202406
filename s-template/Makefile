# 環境変数
include variable.sh

# ディレクトリの場合は/を忘れない!
# 環境によって変わる変数
DIR_DB:=/etc/mysql/
DIR_NGINX:=/etc/nginx/
# /initializeのときに呼ばれるsqlがあるディレクトリ
DIR_SQL_INIT:=/home/isucon/webapp/sql/
DIR_LIB_SYSTEMD:=/lib/systemd/system/
FILE_NGINX_LOG:=/var/log/nginx/access.log
FILE_APP_BIN:=/home/isucon/private_isu/webapp/golang/app
FILE_ENV:=/home/isucon/env.sh
FILE_SERVICE:=/etc/systemd/system/isu-go.service

DIR_APP:=${shell dirname ${FILE_APP_BIN}}/
DIR_SYSTEMD:=${shell dirname ${FILE_SERVICE}}/
NAME_APP_BIN:=${shell basename ${FILE_APP_BIN}}
NAME_ENV:=${shell basename ${FILE_ENV}}
NAME_SERVICE:=${shell basename ${FILE_SERVICE}}

# 定数
SERVER:=${USER}@${IP}
SLACK_CHANNEL:=sample
# 時刻のみ
# time:=${shell date '+%H%M_%S'}
# 年_月日_時分_秒
time:=${shell date '+%y_%m%d_%H%M_%S'}
OUTPUT_PATH:=..


access-db:
	ssh -p ${PORT} ${SERVER} -t  'mysql -h 127.0.0.1 -u isucon --password=isucon isupipe'

ssh:
	ssh -A -p ${PORT} -X ${SERVER} 

ssh-port:
	ssh -p ${PORT} -L 19999:localhost:19999 -L 6060:localhost:6060 -L 1080:localhost:1080 -L 5000:127.0.0.1:5000 ${SERVER}

ssh-initialize:
	ssh -p ${PORT} ${SERVER} -t 'curl -X POST http://localhost:8080/api/initialize'

# ssh-apply-authのときのみ別のユーザーを指定できる
# ex) USER_INIT=ubuntu IP_INIT=123.456.789 make ssh-apply-auth
USER_INIT ?= ${USER}
IP_INIT ?= ${IP}
ssh-apply-auth:
	ssh -i ${KEY_FILE} -p ${PORT} ${USER_INIT}@${IP_INIT} '\
		for i in "kajikentaro" "edge2992" "methylpentane"; do \
			sudo -HSu ${USER} bash -c "mkdir -p ~/.ssh" ; \
			sudo -HSu ${USER} bash -c "curl https://github.com/$$i.keys >> ~/.ssh/authorized_keys" ; \
			curl https://github.com/$$i.keys >> ~/.ssh/authorized_keys ; \
		done \
	'

########## INIT ##########
# 設定ファイルなどを取得してgit管理下に配置する
# 取得する設定：env.sh, nginx, mysql, sql, service, webapp/go
.PHONY: get-conf
get-conf: get-all

########## MAIN ##########
# ベンチマークを走らせる直前に実行する
# ビルド、デプロイ、ログ初期化, リスタート
.PHONY: before-bench
before-bench: app-build rm-logs  deploy-all restart

# ベンチを走らせた後に実行する
# ログの取得, 解析
.PHONY: after-bench
after-bench: nginx-pull nginx-alp

########## BENCH ##########
bench-ssh:
	ssh -A -p ${PORT} -X ${USER}@${BENCH_IP}

bench-port:
	# eval $$(ssh-agent)
	# find ~/.ssh/ -type f -exec grep -l "PRIVATE" {} \; | xargs ssh-add
	ssh -A -p ${PORT} ${USER}@${BENCH_IP} '\
		ssh-add -l && \
		ssh -oStrictHostKeyChecking=no -R 4999:localhost:4999 -4 isucon@${IP} \
	'

# isucon-11q for ansibleは裏でmake bench-portを実行する必要がある
bench:
	mkdir -p bench_result
	ssh -A -p ${PORT} ${USER}@${BENCH_IP} '\
		cd /home/isucon/private_isu.git/benchmarker/bin; \
		./benchmarker -u /home/isucon/private_isu.git/benchmarker/userdata -t http://${IP} \
	' | tee bench_result/${time}.log | slackcat --channel ${SLACK_CHANNEL} -tee 


setup-bench:
	ssh -A -p ${PORT} ${USER}@${BENCH_IP} '\
		/home/isucon/isuumo/bench \
		/home/isucon/isuumo/bench \
	' | tee bench_result/${time}.log


########## pprof ##########
PPROF_OUTPUT:=./pprof
.PHONY: pprof-record
pprof-record:
	mkdir -p ${PPROF_OUTPUT}
	PPROF_OUTPUT=${PPROF_OUTPUT} go tool pprof http://${IP}:6060/debug/pprof/profile?seconds=75

.PHONY: pprof-check
pprof-check:
	$(eval latest := $(shell ls -rt $(PPROF_DIR) | tail -n 1))
	go tool pprof -http=localhost:8090 $(PPROF_DIR)/$(latest)

########## APP ##########
app-build:
	cd ${OUTPUT_PATH}/webapp/go && CGO_ENABLED=0 go build -o ${shell basename ${FILE_APP_BIN}} main.go

app-log:
	ssh -p ${PORT} ${SERVER} '\
		sudo journalctl -f -u ${NAME_SERVICE} -n10 \
	'

########## LOG ##########
nginx-pull:
	mkdir -p ./access_log
	rsync -a -e "ssh -p ${PORT}" --rsync-path="sudo rsync" ${SERVER}:${FILE_NGINX_LOG} ./access_log/${time}.log


.PHONY: rm-logs
rm-logs:
	ssh -p ${PORT} ${SERVER} '\
		sudo rm -f /var/log/nginx/access.log && \
		sudo rm -f /var/log/mysql/mysql-slow.log \
	'

latest_log=$(shell basename `ls access_log 2> /dev/null | sort -r | head -n 1` .log)
latest_log2=$(shell basename `ls access_log 2> /dev/null | sort -r | sed -n '2p'` .log)
nginx-alp:
		mkdir -p ./access_log_alp
		alp json --file=access_log/${latest_log}.log --config=../s-template/alp.config.yml | tee access_log_alp/${latest_log}.log | slackcat --channel ${SLACK_CHANNEL} -tee --filename alp

nginx-alp-diff:
		alp json --file=access_log/${latest_log}.log --dump /tmp/${latest_log}.yaml --config=../s-template/alp.config.yml > /dev/null
		alp json --file=access_log/${latest_log2}.log --dump /tmp/${latest_log2}.yaml --config=../s-template/alp.config.yml > /dev/null
		alp diff /tmp/${latest_log}.yaml /tmp/${latest_log2}.yaml --config=../s-template/alp.config.yml | slackcat --channel ${SLACK_CHANNEL} -tee --filename alp-diff


########## SQL ##########
sql-all: sql-record sql-pull

sql-record:
	ssh -p ${PORT} ${SERVER} '\
		sudo query-digester -duration 75 \
	'

sql-pull:
	ssh -p ${PORT} ${SERVER} '\
		latest_log=`sudo ls /tmp/slow_query_*.digest | sort -r | head -n 1` && \
		sudo cp -f $$latest_log /tmp/${time}.digest && \
		sudo chmod 777 /tmp/${time}.digest \
	'
	mkdir -p ./query_digest
	scp -P ${PORT} ${SERVER}:/tmp/${time}.digest ./query_digest/${time}.digest
	head -n60 ./query_digest/${time}.digest | slackcat --channel ${SLACK_CHANNEL} -tee

########## SETUP ##########
setup-all: setup-local setup-sql-query-digester

NOW_DIR:=$(shell basename `pwd`)
setup-directory:
	mkdir -p ../s1 && cp variable.sh ../s1 && ln -s ../${NOW_DIR}/Makefile ../s1/Makefile
	mkdir -p ../s2 && cp variable.sh ../s2 && ln -s ../${NOW_DIR}/Makefile ../s2/Makefile
	mkdir -p ../s3 && cp variable.sh ../s3 && ln -s ../${NOW_DIR}/Makefile ../s3/Makefile

setup-local:
	sudo apt update
	sudo apt install -y unzip
	# install alp
	cd /tmp && wget https://github.com/tkuchiki/alp/releases/download/v1.0.21/alp_linux_amd64.zip
	unzip -o /tmp/alp_linux_amd64.zip -d /tmp
	sudo install /tmp/alp /usr/local/bin/alp
	# install slackcat
	cd /tmp && curl -Lo slackcat https://github.com/edge2992/slackcat/releases/download/1.7.4/slackcat-1.7.4-linux-amd64
	sudo install /tmp/slackcat /usr/local/bin/slackcat
	# mkdir -p ~/.config/slackcat && cp slackcat.config ~/.config/slackcat/config
	# # install git-crypt
	# sudo apt install -y git-crypt
	# git-crypt unlock

setup-sql-query-digester:
	ssh -p ${PORT} ${SERVER} '\
		sudo apt-get update && \
		sudo apt-get install -y percona-toolkit && \
		sudo wget https://raw.githubusercontent.com/kazeburo/query-digester/main/query-digester -O /usr/local/bin/query-digester && \
		sudo chmod 777 /usr/local/bin/query-digester && \
		echo mysql -u root -e "ALTER USER root@localhost IDENTIFIED BY '';" \
	'

.PHONY: check-server-id
check-server-id:
	@echo $(shell pwd)
	@echo "SERVER=${SERVER}"

# Do not forget / at the end
OUTPUT_DIR_ENV:=${OUTPUT_PATH}/
OUTPUT_DIR_DB_CONF:=${OUTPUT_PATH}/mysql/
OUTPUT_DIR_NGINX_CONF:=${OUTPUT_PATH}/nginx/
OUTPUT_DIR_HOSTS_FILE:=${OUTPUT_PATH}/
OUTPUT_DIR_APP_SOURCE:=${OUTPUT_PATH}/webapp/go/
OUTPUT_DIR_SQL_INIT:=${OUTPUT_PATH}/webapp/sql/
OUTPUT_DIR_LIB_SERVICE_FILE:=${OUTPUT_PATH}/lib-systemd/
OUTPUT_DIR_SERVICE_FILE:=${OUTPUT_PATH}/systemd/
# a example to make settings unique for each server
# OUTPUT_DIR_SERVICE_FILE:=./systemd/

get-all: check-server-id get-service-file get-lib-service-file get-envsh get-nginx-conf get-db-conf get-hosts-file get-app-source 
	# get-sql-init

get-envsh:
	mkdir -p ${OUTPUT_DIR_ENV}
	rsync -a --delete -e "ssh -p ${PORT}" --rsync-path="sudo rsync" ${SERVER}:${FILE_ENV} ${OUTPUT_DIR_ENV}

get-db-conf:
	mkdir -p ${OUTPUT_DIR_DB_CONF}
	rsync -a --delete -e "ssh -p ${PORT}" --rsync-path="sudo rsync" ${SERVER}:${DIR_DB} ${OUTPUT_DIR_DB_CONF}

get-nginx-conf:
	mkdir -p ${OUTPUT_DIR_NGINX_CONF}
	rsync -a --delete -e "ssh -p ${PORT}" --rsync-path="sudo rsync" ${SERVER}:${DIR_NGINX} ${OUTPUT_DIR_NGINX_CONF}

# not enable at first
get-memcached-conf:
	mkdir -p ${OUTPUT_DIR_ENV}
	rsync -a --delete -e "ssh -p ${PORT}" --rsync-path="sudo rsync" ${SERVER}:/etc/memcached.conf ./etc/

get-service-file:
	mkdir -p ${OUTPUT_DIR_SERVICE_FILE}
	rsync -a --delete -e "ssh -p ${PORT}" --rsync-path="sudo rsync" ${SERVER}:${DIR_SYSTEMD} ${OUTPUT_DIR_SERVICE_FILE}

get-lib-service-file:
	mkdir -p ${OUTPUT_DIR_LIB_SERVICE_FILE}
	rsync -a --delete -e "ssh -p ${PORT}" --rsync-path="sudo rsync" ${SERVER}:${DIR_LIB_SYSTEMD} ${OUTPUT_DIR_LIB_SERVICE_FILE}

get-hosts-file:
	mkdir -p ${OUTPUT_DIR_HOSTS_FILE}
	rsync -a --delete -e "ssh -p ${PORT}" --rsync-path="sudo rsync" ${SERVER}:/etc/hosts ${OUTPUT_DIR_HOSTS_FILE}

get-app-source:
	mkdir -p ${OUTPUT_DIR_APP_SOURCE}
	rsync -a --delete -e "ssh -p ${PORT}" --rsync-path="sudo rsync" ${SERVER}:${DIR_APP} ${OUTPUT_DIR_APP_SOURCE}

get-sql-init:
	mkdir -p ${OUTPUT_DIR_SQL_INIT}
	rsync -P -a --delete -e "ssh -p ${PORT}" --rsync-path="sudo rsync" ${SERVER}:${DIR_SQL_INIT}/* ${OUTPUT_DIR_SQL_INIT}


deploy-all: check-server-id deploy-service-file deploy-lib-service-file deploy-envsh deploy-nginx-conf deploy-db-conf deploy-hosts-file deploy-app-source 
	# deploy-sql-init


deploy-envsh:
	rsync -a --delete -e "ssh -p ${PORT}" --rsync-path="sudo rsync"  ${OUTPUT_DIR_ENV}${NAME_ENV} ${SERVER}:${FILE_ENV}

deploy-db-conf:
	rsync -a --delete -e "ssh -p ${PORT}" --rsync-path="sudo rsync" ${OUTPUT_DIR_DB_CONF} ${SERVER}:${DIR_DB} 

deploy-nginx-conf:
	rsync -a --delete -e "ssh -p ${PORT}" --rsync-path="sudo rsync" ${OUTPUT_DIR_NGINX_CONF} ${SERVER}:${DIR_NGINX}

# not enable at first
deploy-memcached-conf:
	rsync -a --delete -e "ssh -p ${PORT}" --rsync-path="sudo rsync" ./etc/memcached.conf ${SERVER}:/etc/memcached.conf

deploy-service-file:
	rsync -a --delete -e "ssh -p ${PORT}" --rsync-path="sudo rsync" ${OUTPUT_DIR_SERVICE_FILE} ${SERVER}:${DIR_SYSTEMD}

deploy-lib-service-file:
	rsync -a --delete -e "ssh -p ${PORT}" --rsync-path="sudo rsync" ${OUTPUT_DIR_LIB_SERVICE_FILE} ${SERVER}:${DIR_LIB_SYSTEMD}

deploy-hosts-file:
	rsync -a --delete -e "ssh -p ${PORT}" --rsync-path="sudo rsync" ${OUTPUT_DIR_HOSTS_FILE}/hosts ${SERVER}:/etc/hosts 

deploy-app-source:
	rsync -a --delete -e "ssh -p ${PORT}" --rsync-path="sudo rsync" ${OUTPUT_DIR_APP_SOURCE} ${SERVER}:${DIR_APP}

deploy-sql-init:
	rsync -P -a --delete -e "ssh -p ${PORT}" --rsync-path="sudo rsync" ${OUTPUT_DIR_SQL_INIT} ${SERVER}:${DIR_SQL_INIT}


########## UTILITY ##########

.PHONY: restart
restart:
	ssh -p ${PORT} ${SERVER} '\
	sudo systemctl daemon-reload && \
	sudo systemctl restart $(NAME_SERVICE) && \
	sudo systemctl restart mysql && \
	sudo systemctl restart nginx \
	'

.PHONY: restart-memcached
restart-memcached:
	ssh -p ${PORT} ${SERVER} '\
	sudo systemctl restart memcached \
	'
