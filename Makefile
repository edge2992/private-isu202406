# 環境変数
include env.sh

# 変数
alp_matching_group = ''

# 定数
SERVER:=${USER}@${IP}
time:=${shell date '+%H%M_%S'}

# 環境によって変わる変数
DB_PATH:=/etc/mysql
NGINX_PATH:=/etc/nginx
SYSTEMD_PATH:=/etc/systemd/system
BIN_NAME:=isucondition
SERVICE_NAME:=$(BIN_NAME).go.service

ssh:
	ssh -i ${KEY_FILE} -p ${PORT} ${SERVER} 

ssh-port:
	ssh -i ${KEY_FILE} -p ${PORT} -L 19999:localhost:19999 -L 6060:localhost:6060 -L 1080:localhost:1080 ${SERVER}

########## BENCH ##########
bench-ssh:
	ssh -A -i ${KEY_FILE} -p ${PORT} ${BE}

bench:
	ssh -i ${KEY_FILE} -p ${PORT} ${USER}@${BENCH_IP} '\
		sudo /home/isucon/private_isu.git/benchmarker/bin/benchmarker -u /home/isucon/private_isu.git/benchmarker/userdata -t http://${IP} \
	'
bench-local:
	docker run --network host --add-host host.docker.internal:host-gateway -i private-isu-benchmarker /opt/go/bin/benchmarker -t http://${IP} -u /opt/go/userdata

pprof:
	ssh -i ${KEY_FILE} -p ${PORT} ${SERVER} '\
		/home/isucon/.local/go/bin/go tool pprof -http=0.0.0.0:1080 /home/isucon/private_isu/webapp/golang/app http://localhost:6060/debug/pprof/profile \
	'


########## SPEED TEST ##########
speed-test-download:
	ssh -i ${KEY_FILE} -p ${PORT} ${SERVER} 'dd if=/dev/zero bs=1M count=100' | dd of=/dev/null

speed-test-upload:
	dd if=/dev/zero bs=1M count=100 | ssh -i ${KEY_FILE} -p ${PORT} ${SERVER} 'dd of=/dev/null'

########## APP ##########
app:
	cd ./golang && go build -o /tmp/app ./app.go
	scp -i ${KEY_FILE} -P ${PORT} /tmp/app ${SERVER}:/tmp/app
	ssh -i ${KEY_FILE} -p ${PORT} ${SERVER} '\
		sudo systemctl stop isu-go && \
		sudo cp -r /tmp/app /home/isucon/private_isu/webapp/golang/app && \
		sudo systemctl start isu-go \
	'

app-pull-source:
	mkdir -p source
	scp -r -i ${KEY_FILE} -P ${PORT} ${SERVER}:/home/isucon/private_isu/webapp/golang ./

app-log:
	ssh -i ${KEY_FILE} -p ${PORT} ${SERVER} '\
		sudo journalctl -f -u isu-go \
	'



########## LOG ##########
nginx-all: nginx-pull nginx-rm nginx-alp

nginx-pull:
	ssh -i ${KEY_FILE} -p ${PORT} ${SERVER} '\
		sudo cp /var/log/nginx/access.log /tmp && \
		sudo chmod 666 /tmp/access.log \
	'
	mkdir -p access_log
	scp -i ${KEY_FILE} -P ${PORT} ${SERVER}:/tmp/access.log ./access_log/${time}.log

nginx-rm:
	ssh -i ${KEY_FILE} -p ${PORT} ${SERVER} '\
		sudo service nginx stop && \
		: | sudo tee /var/log/nginx/access.log && \
		sudo service nginx start \
	'

latest_log:=$(shell ls access_log | sort -r | head -n 1)
nginx-alp:
	alp json --file=access_log/${latest_log} --config=./alp.config.yml | tee access_log_alp/${latest_log}

########## SQL ##########
sql-all: sql-record sql-pull

sql-record:
	ssh -i ${KEY_FILE} -p ${PORT} ${SERVER} '\
		sudo query-digester -duration 75 \
	'

sql-pull:
	ssh -i ${KEY_FILE} -p ${PORT} ${SERVER} '\
		latest_log=`sudo ls /tmp/slow_query_*.digest | sort -r | head -n 1` && \
		sudo cp -f $$latest_log /tmp/${time}.digest && \
		sudo chmod 777 /tmp/${time}.digest \
	'
	scp -i ${KEY_FILE} -P ${PORT} ${SERVER}:/tmp/${time}.digest ./query_digest/${time}.digest

########## SETUP ##########
setup-all: setup-docker setup-local setup-nginx-conf setup-sql-query-digester

setup-netdata:
	ssh -i ${KEY_FILE} -p ${PORT} ${SERVER} '\
		sudo apt update && \
		sudo apt install -y netdata \
	'

setup-local:
	mkdir -p access_log
	mkdir -p access_log_alp
	mkdir -p query_digest

	sudo apt update
	sudo apt install -y unzip
	cd /tmp && wget https://github.com/tkuchiki/alp/releases/download/v1.0.8/alp_linux_amd64.zip
	unzip -o /tmp/alp_linux_amd64.zip -d /tmp
	sudo install /tmp/alp /usr/local/bin/alp

setup-sql-query-digester:
	ssh -i ${KEY_FILE} -p ${PORT} ${SERVER} '\
		sudo apt-get update && \
		sudo apt-get install -y percona-toolkit && \
		sudo wget https://raw.githubusercontent.com/kazeburo/query-digester/main/query-digester -O /usr/local/bin/query-digester && \
		sudo chmod 777 /usr/local/bin/query-digester && \
		echo mysql -u root -e "ALTER USER root@localhost IDENTIFIED BY '';" \
	'

setup-nginx-conf:
	scp -i ${KEY_FILE} -P ${PORT} ./config_files/nginx.conf ${SERVER}:/tmp/nginx.conf
	ssh -i ${KEY_FILE} -p ${PORT} ${SERVER} '\
		cat /tmp/nginx.conf | sudo tee /etc/nginx/nginx.conf > /dev/null && \
		sudo service nginx restart \
	'

pull-nginx-conf:
	ssh -i ${KEY_FILE} -p ${PORT} ${SERVER} '\
		sudo cat /etc/nginx/nginx.conf > /tmp/nginx.conf \
	'
	scp -i ${KEY_FILE} -P ${PORT} ${SERVER}:/tmp/nginx.conf ./config_files/nginx.conf

setup-docker:
	# install application
	cd ~/private-isu/webapp/ && sudo docker compose up -d --build
	cd ~/private-isu/webapp/ && sudo docker compose exec app apt-get update
	cd ~/private-isu/webapp/ && sudo docker compose exec app apt install vim openssh-server nginx sudo -y
	cd ~/private-isu/webapp/ && sudo docker compose exec app service nginx start
	cd ~/private-isu/webapp/ && sudo docker compose exec app service ssh start

	# create user
	cd ~/private-isu/webapp/ && sudo docker compose exec -u isucon app mkdir -p /home/${USER}/.ssh
	cd ~/private-isu/webapp/ && sudo docker compose cp ~/.ssh/id_ed25519.pub app:/home/${USER}/.ssh/authorized_keys
	cd ~/private-isu/webapp/ && sudo docker compose exec app chown ${USER}:${USER} /home/${USER}/.ssh/authorized_keys
	: > ~/.ssh/known_hosts

	# DB
	cd ~/private-isu/webapp/ && sudo docker compose exec mysql apt-get update
	cd ~/private-isu/webapp/ && sudo docker compose exec mysql apt install vim openssh-server -y
	cd ~/private-isu/webapp/ && sudo docker compose exec mysql service ssh start
	cd ~/private-isu/webapp/ && sudo docker compose exec -u isucon mysql mkdir -p /home/${USER}/.ssh
	cd ~/private-isu/webapp/ && sudo docker compose cp ~/.ssh/id_ed25519.pub mysql:/home/${USER}/.ssh/authorized_keys
	cd ~/private-isu/webapp/ && sudo docker compose exec mysql chown ${USER}:${USER} /home/${USER}/.ssh/authorized_keys
	: > ~/.ssh/known_hosts
	cd ~/private-isu/webapp/ && echo 'ALTER USER root@localhost IDENTIFIED BY "";' | sudo docker compose exec -T mysql mysql -u root -proot

########## CONFIG ##########
get-db-conf:
	ssh -i ${KEY_FILE} -p ${PORT} ${SERVER} '\
		mkdir -p /tmp/etc/mysql && \
		sudo cp -Rpf $(DB_PATH)/* /tmp/etc/mysql && \
		sudo chmod -R +r /tmp/etc/ \
	'
	scp -r -i ${KEY_FILE} -P ${PORT} ${SERVER}:/tmp/etc/mysql ./config_files/

get-nginx-conf:
	ssh -i ${KEY_FILE} -p ${PORT} ${SERVER} '\
		mkdir -p /tmp/etc/nginx && \
		sudo cp -Rpf $(NGINX_PATH)/* /tmp/etc/nginx && \
		sudo chmod -R +r /tmp/etc/ \
	'
	mkdir -p ./config_files/nginx
	scp -r -i ${KEY_FILE} -P ${PORT} ${SERVER}:/tmp/etc/nginx ./config_files/

get-service-file:
	ssh -i ${KEY_FILE} -p ${PORT} ${SERVER} '\
		mkdir -p /tmp/etc/systemd/system/ && \
		sudo cp -Rpf $(SYSTEMD_PATH)/$(SERVICE_NAME) /tmp/etc/systemd/system/ && \
		sudo chmod -R +r /tmp/etc/ \
	'
	scp -r -i ${KEY_FILE} -P ${PORT} ${SERVER}:/tmp/etc/systemd ./config_files/

# TODO: 動作未確認
deploy-db-conf:
	ssh -i ${KEY_FILE} -p ${PORT} ${SERVER} '\
		sudo rm -rf /tmp/etc/mysql \
	'
	scp -r -i ${KEY_FILE} -P ${PORT} ./config_files/mysql ${SERVER}:/tmp/etc/
	ssh -i ${KEY_FILE} -p ${PORT} ${SERVER} '\
		sudo cp -Rpf /tmp/etc/mysql/* $(DB_PATH) \
	'

deploy-nginx-conf:
	ssh -i ${KEY_FILE} -p ${PORT} ${SERVER} '\
		sudo rm -rf /tmp/etc/nginx && \
		mkdir -p /tmp/etc/nginx \
	'
	scp -r -i ${KEY_FILE} -P ${PORT} ./config_files/nginx ${SERVER}:/tmp/etc
	ssh -i ${KEY_FILE} -p ${PORT} ${SERVER} '\
		sudo cp -Rpf /tmp/etc/nginx/* $(NGINX_PATH) && \
		sudo service nginx restart \
	'

# TODO: 動作未確認
deploy-service-file:
	ssh -i ${KEY_FILE} -p ${PORT} ${SERVER} '\
		sudo rm -r /tmp/etc/systemd \
	'
	scp -r -i ${KEY_FILE} -P ${PORT} ./config_files/systemd ${SERVER}:/tmp/etc/
	ssh -i ${KEY_FILE} -p ${PORT} ${SERVER} '\
		sudo cp -Rpf /tmp/etc/systemd/system/* $(SYSTEMD_PATH)/$(SERVICE_NAME) && \
	'
	

# FROM https://github.com/oribe1115/traP-isucon-newbie-handson2022/blob/main/Makefile

# 変数定義 ------------------------

# SERVER_ID: env.sh内で定義

# 問題によって変わる変数
BUILD_DIR:=/home/isucon/webapp/go


NGINX_LOG:=/var/log/nginx/access.log
DB_SLOW_LOG:=/var/log/mysql/mariadb-slow.log


# メインで使うコマンド ------------------------

# サーバーの環境構築　ツールのインストール、gitまわりのセットアップ
.PHONY: setup
# setup: install-tools git-setup

# 設定ファイルなどを取得してgit管理下に配置する
.PHONY: get-conf
get-conf: check-server-id get-db-conf get-nginx-conf get-service-file get-envsh

# リポジトリ内の設定ファイルをそれぞれ配置する
.PHONY: deploy-conf
deploy-conf: check-server-id deploy-db-conf deploy-nginx-conf deploy-service-file deploy-envsh

# slow queryを確認する
.PHONY: slow-query
slow-query:
	sudo pt-query-digest $(DB_SLOW_LOG)

# alpでアクセスログを確認する
.PHONY: alp
alp:
	sudo alp ltsv --file=$(NGINX_LOG) --config=/home/isucon/tool-config/alp/config.yml

# pprofで記録する
.PHONY: pprof-record
pprof-record:
	go tool pprof http://localhost:6060/debug/pprof/profile

# pprofで確認する
.PHONY: pprof-check
pprof-check:
	$(eval latest := $(shell ls -rt pprof/ | tail -n 1))
	go tool pprof -http=localhost:8090 pprof/$(latest)

# DBに接続する
.PHONY: access-db
access-db:
	mysql -h $(MYSQL_HOST) -P $(MYSQL_PORT) -u $(MYSQL_USER) -p$(MYSQL_PASS) $(MYSQL_DBNAME)

# 主要コマンドの構成要素 ------------------------

.PHONY: install-tools
install-tools:
	sudo apt update
	sudo apt upgrade
	sudo apt install -y percona-toolkit dstat git unzip snapd graphviz tree

	# alpのインストール
	wget https://github.com/tkuchiki/alp/releases/download/v1.0.9/alp_linux_amd64.zip
	unzip alp_linux_amd64.zip
	sudo install alp /usr/local/bin/alp
	rm alp_linux_amd64.zip alp

.PHONY: git-setup
git-setup:
	# git用の設定は適宜変更して良い
	git config --global user.email "isucon@example.com"
	git config --global user.name "isucon"

	# deploykeyの作成
	ssh-keygen -t ed25519

.PHONY: check-server-id
check-server-id:
ifdef SERVER_ID
	@echo "SERVER_ID=$(SERVER_ID)"
else
	@echo "SERVER_ID is unset"
	@exit 1
endif

.PHONY: set-as-s1
set-as-s1:
	echo "SERVER_ID=s1" >> env.sh

.PHONY: set-as-s2
set-as-s2:
	echo "SERVER_ID=s2" >> env.sh

.PHONY: set-as-s3
set-as-s3:
	echo "SERVER_ID=s3" >> env.sh


.PHONY: get-envsh
get-envsh:
	cp ~/env.sh ~/$(SERVER_ID)/home/isucon/env.sh


.PHONY: deploy-envsh
deploy-envsh:
	cp ~/$(SERVER_ID)/home/isucon/env.sh ~/env.sh

.PHONY: build
build:
	cd $(BUILD_DIR); \
	go build -o $(BIN_NAME)

.PHONY: restart
restart:
	sudo systemctl daemon-reload
	sudo systemctl restart $(SERVICE_NAME)
	sudo systemctl restart mysql
	sudo systemctl restart nginx

.PHONY: mv-logs
mv-logs:
	$(eval when := $(shell date "+%s"))
	mkdir -p ~/logs/$(when)
	sudo test -f $(NGINX_LOG) && \
		sudo mv -f $(NGINX_LOG) ~/logs/nginx/$(when)/ || echo ""
	sudo test -f $(DB_SLOW_LOG) && \
		sudo mv -f $(DB_SLOW_LOG) ~/logs/mysql/$(when)/ || echo ""

.PHONY: watch-service-log
watch-service-log:
	sudo journalctl -u $(SERVICE_NAME) -n10 -f
