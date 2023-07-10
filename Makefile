# 環境変数
USER:=isucon
IP:=ec2-3-112-56-103.ap-northeast-1.compute.amazonaws.com
KEY_FILE:=~/.ssh/r-pc-win.pem

# 変数
alp_matching_group = ''

# 定数
SERVER:=${USER}@${IP}
time:=${shell date '+%H%M_%S'}

setup:
	mkdir access_log
	mkdir access_log_alp

ssh:
	ssh -i ${KEY_FILE} ${SERVER} 

log-all: log-pull log-rm

log-pull:
	ssh -i ${KEY_FILE} ${SERVER} \
		'sudo cp /var/log/nginx/access.log /tmp && sudo chmod 666 /tmp/access.log'
	scp -i ${KEY_FILE} ${SERVER}:/tmp/access.log ./access_log/${time}.log

log-rm:
	ssh -i ${KEY_FILE} ${SERVER} \
		': | sudo tee /var/log/nginx/access.log'

latest_log:=$(shell ls access_log | sort -r | head -n 1)
log-alp:
	alp json --file=access_log/${latest_log} --config=./alp.config.yml

setup:
	sudo apt update
	sudo apt install -y unzip
	cd /tmp && wget https://github.com/tkuchiki/alp/releases/download/v1.0.9/alp_linux_amd64.zip
	unzip /tmp/alp_linux_amd64.zip
	sudo install alp /usr/local/bin/alp
	rm alp_linux_amd64.zip alp

## TODO

ssh-v:
	ssh ubuntu@18.181.250.99 -i ~/.ssh/r-pc-win.pem

bench:
	ssh ubuntu@18.181.250.99 -i ~/.ssh/r-pc-win.pem sudo -u isucon /home/isucon/private_isu.git/benchmarker/bin/benchmarker -u /home/isucon/private_isu.git/benchmarker/userdata -t http://52.199.234.186/


# FROM https://github.com/oribe1115/traP-isucon-newbie-handson2022/blob/main/Makefile

include env.sh
# 変数定義 ------------------------

# SERVER_ID: env.sh内で定義

# 問題によって変わる変数
BIN_NAME:=isucondition
BUILD_DIR:=/home/isucon/webapp/go
SERVICE_NAME:=$(BIN_NAME).go.service

DB_PATH:=/etc/mysql
NGINX_PATH:=/etc/nginx
SYSTEMD_PATH:=/etc/systemd/system

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

# ベンチマークを走らせる直前に実行する
.PHONY: bench
bench: check-server-id mv-logs build deploy-conf restart watch-service-log

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

.PHONY: get-db-conf
get-db-conf:
	sudo cp -R $(DB_PATH)/* ~/$(SERVER_ID)/etc/mysql
	sudo chown $(USER) -R ~/$(SERVER_ID)/etc/mysql

.PHONY: get-nginx-conf
get-nginx-conf:
	sudo cp -R $(NGINX_PATH)/* ~/$(SERVER_ID)/etc/nginx
	sudo chown $(USER) -R ~/$(SERVER_ID)/etc/nginx

.PHONY: get-service-file
get-service-file:
	sudo cp $(SYSTEMD_PATH)/$(SERVICE_NAME) ~/$(SERVER_ID)/etc/systemd/system/$(SERVICE_NAME)
	sudo chown $(USER) ~/$(SERVER_ID)/etc/systemd/system/$(SERVICE_NAME)

.PHONY: get-envsh
get-envsh:
	cp ~/env.sh ~/$(SERVER_ID)/home/isucon/env.sh

.PHONY: deploy-db-conf
deploy-db-conf:
	sudo cp -R ~/$(SERVER_ID)/etc/mysql/* $(DB_PATH)

.PHONY: deploy-nginx-conf
deploy-nginx-conf:
	sudo cp -R ~/$(SERVER_ID)/etc/nginx/* $(NGINX_PATH)

.PHONY: deploy-service-file
deploy-service-file:
	sudo cp ~/$(SERVER_ID)/etc/systemd/system/$(SERVICE_NAME) $(SYSTEMD_PATH)/$(SERVICE_NAME)

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
