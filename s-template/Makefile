# 環境変数
include variable.sh

# ディレクトリの場合は/を忘れない!
# 環境によって変わる変数
DIR_DB:=/etc/mysql
DIR_NGINX:=/etc/nginx
# /initializeのときに呼ばれるsqlがあるディレクトリ
DIR_SQL_INIT:=/home/isucon/webapp/sql
FILE_NGINX_LOG:=/var/log/nginx/access.log
FILE_APP_BIN:=/home/isucon/webapp/go/isucondition
FILE_ENV:=/home/isucon/env.sh
FILE_SERVICE:=/etc/systemd/system/isucondition.go.service

DIR_APP:=${shell dirname ${FILE_APP_BIN}}/
DIR_SYSTEMD:=${shell dirname ${FILE_SERVICE}}/
NAME_SERVICE:=${shell basename ${FILE_SERVICE}}

# 定数
SERVER:=${USER}@${IP}
# 時刻のみ
# time:=${shell date '+%H%M_%S'}
# 年_月日_時分_秒
time:=${shell date '+%y_%m%d_%H%M_%S'}
OUTPUT_PATH:=..


access-db:
	ssh -p ${PORT} ${SERVER} -t  'mysql -h 127.0.0.1 -u isucari --password=isucari isucari'

ssh:
	ssh -A -p ${PORT} -X ${SERVER} 

ssh-port:
	ssh -p ${PORT} -L 19999:localhost:19999 -L 6060:localhost:6060 -L 1080:localhost:1080 -L 5000:127.0.0.1:5000 ${SERVER}

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
		cd /home/isucon/isuumo/bench; \
		./bench --target-url http://${IP} --data-dir ../initial-data --fixture-dir ../webapp/fixture \
	' | tee bench_result/${time}.log

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
		alp json --file=access_log/${latest_log}.log --config=../s-template/alp.config.yml | tee access_log_alp/${latest_log}.log

nginx-alp-diff:
		alp json --file=access_log/${latest_log}.log --dump /tmp/${latest_log}.yaml --config=../s-template/alp.config.yml > /dev/null
		alp json --file=access_log/${latest_log2}.log --dump /tmp/${latest_log2}.yaml --config=../s-template/alp.config.yml > /dev/null
		alp diff /tmp/${latest_log}.yaml /tmp/${latest_log2}.yaml --config=../s-template/alp.config.yml


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
	cd /tmp && wget https://github.com/tkuchiki/alp/releases/download/v1.0.21/alp_linux_amd64.zip
	unzip -o /tmp/alp_linux_amd64.zip -d /tmp
	sudo install /tmp/alp /usr/local/bin/alp

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
OUTPUT_PATH_ENVSH:=./env.sh
OUTPUT_PATH_DB_CONF:=${OUTPUT_PATH}/mysql/
OUTPUT_PATH_NGINX_CONF:=./mysql/
OUTPUT_PATH_SERVICE_FILE:=./systemd/
OUTPUT_PATH_HOSTS_FILE:=./hosts
OUTPUT_PATH_APP_SOURCE:=${OUTPUT_PATH}/webapp/go/
OUTPUT_PATH_SQL_INIT:=${OUTPUT_PATH}/webapp/sql/

get-all: check-server-id get-service-file get-envsh get-nginx-conf get-db-conf get-hosts-file get-app-source get-sql-init

get-envsh:
	mkdir -p ${OUTPUT_PATH_ENVSH}
	rsync -a --delete -e "ssh -p ${PORT}" --rsync-path="sudo rsync" ${SERVER}:${FILE_ENV} ${OUTPUT_PATH_ENVSH}

get-db-conf:
	mkdir -p ${OUTPUT_PATH_DB_CONF}
	rsync -a --delete -e "ssh -p ${PORT}" --rsync-path="sudo rsync" ${SERVER}:${DIR_DB} ${OUTPUT_PATH_DB_CONF}

get-nginx-conf:
	mkdir -p ${OUTPUT_PATH_NGINX_CONF}
	rsync -a --delete -e "ssh -p ${PORT}" --rsync-path="sudo rsync" ${SERVER}:${DIR_NGINX} ${OUTPUT_PATH_NGINX_CONF}

get-service-file:
	mkdir -p ${OUTPUT_PATH_SERVICE_FILE}
	rsync -a --delete -e "ssh -p ${PORT}" --rsync-path="sudo rsync" ${SERVER}:${DIR_SYSTEMD} ${OUTPUT_PATH_SERVICE_FILE}

get-hosts-file:
	mkdir -p ${OUTPUT_PATH_HOSTS_FILE}
	rsync -a --delete -e "ssh -p ${PORT}" --rsync-path="sudo rsync" ${SERVER}:/etc/hosts ${OUTPUT_PATH_HOSTS_FILE}

get-app-source:
	mkdir -p ${OUTPUT_PATH_APP_SOURCE}
	rsync -a --delete -e "ssh -p ${PORT}" --rsync-path="sudo rsync" ${SERVER}:${DIR_APP} ${OUTPUT_PATH_APP_SOURCE}

get-sql-init:
	mkdir -p ${OUTPUT_PATH_SQL_INIT}
	rsync -P -a --delete -e "ssh -p ${PORT}" --rsync-path="sudo rsync" ${SERVER}:${DIR_SQL_INIT}/* ${OUTPUT_PATH_SQL_INIT}


deploy-all: check-server-id deploy-service-file deploy-envsh deploy-nginx-conf deploy-db-conf deploy-hosts-file deploy-app-source deploy-sql-init


deploy-envsh:
	rsync -a --delete -e "ssh -p ${PORT}" --rsync-path="sudo rsync"  ${OUTPUT_PATH_ENVSH} ${SERVER}:${FILE_ENV}

deploy-db-conf:
	rsync -a --delete -e "ssh -p ${PORT}" --rsync-path="sudo rsync" ${OUTPUT_PATH_DB_CONF} ${SERVER}:${DIR_DB} 

deploy-nginx-conf:
	rsync -a --delete -e "ssh -p ${PORT}" --rsync-path="sudo rsync" ${OUTPUT_PATH_NGINX_CONF} ${SERVER}:${DIR_NGINX}

deploy-service-file:
	rsync -a --delete -e "ssh -p ${PORT}" --rsync-path="sudo rsync" ${OUTPUT_PATH_SERVICE_FILE} ${SERVER}:${DIR_SYSTEMD}

deploy-hosts-file:
	rsync -a --delete -e "ssh -p ${PORT}" --rsync-path="sudo rsync" ${OUTPUT_PATH_HOSTS_FILE} ${SERVER}:/etc/hosts 

deploy-app-source:
	rsync -a --delete -e "ssh -p ${PORT}" --rsync-path="sudo rsync" ${OUTPUT_PATH_APP_SOURCE} ${SERVER}:${DIR_APP}

deploy-sql-init:
	rsync -P -a --delete -e "ssh -p ${PORT}" --rsync-path="sudo rsync" ${OUTPUT_PATH_SQL_INIT} ${SERVER}:${DIR_SQL_INIT}


########## UTILITY ##########

.PHONY: restart
restart:
	ssh -p ${PORT} ${SERVER} '\
	sudo systemctl daemon-reload && \
	sudo systemctl restart $(NAME_SERVICE) && \
	sudo systemctl restart mysql && \
	sudo systemctl restart nginx \
	'
