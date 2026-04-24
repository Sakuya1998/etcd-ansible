.PHONY: test-docker-compose

test-docker-compose:
	bash tests/docker-compose/test.sh

test-docker-compose-tls:
	bash tests/docker-compose/test-tls.sh
