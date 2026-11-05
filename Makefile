.PHONY: help setup vm provision monitoring verify backup restore-drill test check stop destroy publish
ANSIBLE_PLAYBOOK ?= $(CURDIR)/.venv/bin/ansible-playbook
export ANSIBLE_LOCAL_TEMP := $(CURDIR)/.cache/ansible/tmp
COMPOSE = docker compose -f monitoring/docker-compose.yml
help:
	@echo "setup vm monitoring provision verify backup restore-drill check test stop destroy publish"
setup:
	python3 -m venv .venv
	.venv/bin/pip install -r requirements-dev.txt
vm:
	./scripts/vm.sh up
monitoring:
	./scripts/secrets.sh
	$(COMPOSE) up -d
provision: monitoring
	cd ansible && $(ANSIBLE_PLAYBOOK) playbooks/site.yml
verify:
	.venv/bin/python scripts/verify.py
backup:
	./scripts/vm.sh ssh sudo /usr/local/sbin/sre-backup.sh
restore-drill:
	./scripts/vm.sh ssh sudo /usr/local/sbin/sre-restore-drill.sh
check:
	for script in scripts/*.sh; do bash -n "$$script"; done
	$(COMPOSE) config --quiet
	cd ansible && $(ANSIBLE_PLAYBOOK) playbooks/site.yml --syntax-check
test:
	.venv/bin/python -m unittest discover -s tests -v
stop:
	$(COMPOSE) down
	./scripts/vm.sh stop
destroy: stop
	./scripts/vm.sh destroy
publish:
	./scripts/publish.sh
