v=v1
links:
	@echo "Grafana UI: http://localhost:3000"

run-project:
	# run project

build-api:
	docker build -t mlops-api-$(v) -f ./src/api/$(v)/Dockerfile .


test-api:
	curl -X POST "https://localhost/predict" \
     -H "Content-Type: application/json" \
     -d '{"sentence": "Oh yeah, that was soooo cool!"}' \
	 --user admin:admin \
     --cacert ./deployments/nginx/certs/nginx.crt;

#docker image for nginx proxy server
start-project:
	docker compose -p mlopsv up -d --build

log-project:
	docker compose -p mlopsv logs
	
stop-project:
	docker compose -p mlopsv down


test:
	tests/run_tests.sh