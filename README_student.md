# examen NGINX - Lionel GONTIER 

## 1. progression dans la résolution
mise en place du fork 
prise en main, configuration du test dans le makefile et execution, tout FAIL sauf le test Rate Limiting qui PASS insolament alors que rien n'est joué
préparation des Dockerfiles en v1 et v2 sur image slim standard, partage des requirements
adapatation des main.py api pour health check pour valider les depends on
configuration des deux Dockerfiles correspondant sur port 8001 et 8002
completion du docker-compose avec les containers manquant mlops_v1 v2 nginx_exporter
- mise en place des branchements dockers, des replications correspondante respectives 3 et 1, ports respectif et healthcheck
- chaque container loadera un model
- mise en place du nginx en reverse proxy 
- mise en place de certificat - sur les machines dont je dispose j'ai préparé un CA - certificat Authority
    on regardera s'il faut regénéré les certificats en fonction des IP ou plages CIRD impliqué (a posteriori visiblement non)
- le démarage de nginx est conditionné au démarrage des deux vm sous jacente v1 et v2
- le nginx_exporter est standard et scrapera pour grafana via prometheus les données de télémétries sur le port 8081 qui sera dédié aux statistiques machines
- prometheus et grafana seront déployé depuis leur image latest.

le docker nginx est standard exposera trois port 80 443 et 8081(mesures)
le htpassword à l'air ok, sinon sera refait

validation de la config nginx

## 2. etude du routage conditionnel
renomage des api api-v1 et api-v2
X-Experiment-Group: debug

X-Forwarded-Proto becomes $http_x_forwarded_proto. 
ref https://stackoverflow.com/questions/26223733/how-to-make-nginx-redirect-based-on-the-value-of-a-header

X-Experiment-Group -> $http_x_experiment_Group
```yaml
server {
    listen 80;
    server_name example.com; # Replace this with your own hostname
    if ($http_x_experiment_Group = "debug") {
        return 301 https://example.com$request_uri;
    }

    # Rest of configuration goes here... 
}
```

if est controversé, map semble plus judicieux.

Option map pas mal, mixé avec l'upstream du cours ou on proxypassait vers un upstream plutôt - et ça gère le port en sus
==>
```yaml
upstream api_v1 {server mlops-api-v1:8001;}
upstream api_v2 {server mlops-api-v2:8002;}
```

# $http_x_experiment_group = valeur du header X-Experiment-Group
# nginx passe en lowercase et transforme - en _ automatiquement pour les headers

```yaml
map $http_x_experiment_group $api_backend {
    "debug"   "api_v2";
    default   "api_v1";
}
...
    server {
        listen 80;

        location /predict {
            proxy_pass http://$api_backend;  # ← variable résolue par map
            resolver 127.0.0.11;             # ← DNS Docker, obligatoire avec variable
        }
    }
...
```
## 3. choix de configuration
Bon je reste sur une configuration simple, deux images et deux docker séparé sans considération d'optimisation pour l'instant.

Préparation du Makefile et passage en test
On commence par un build avec un variable apiVersion par défaut à v1
on construit les deux images docker v1 et v2

```bash
  #une variable overridable v existe dans le Makefile avec valeur par defaut à v1
  make build-api
  make build-api v=v2

  make start-project 
  make stop-project 

```


## 4. Résumé des commandes de debug pour la session de mise au point
Au premier test, un 404 sur le v2 car il manquait un health endpoint dans le main de v2
Puis un ; manquant dans le upstream de nginx.conf

les commandes les plus directe et marquante pour analyser des logs sont:

```bash
docker ps -a
docker logs nginx_revproxy
```

## 5. le test final roula du premier coup - ouf !
```bash
$ make test

--- Running Test 1: Nominal Prediction (API v1) ---
[PASS] API v1 returned HTTP 200 OK.

--- Running Test 2: A/B Routing (API v2) ---
[PASS] API v2 response contains 'prediction_proba_dict'.

--- Running Test 3: Authentication Failure ---
[PASS] Authentication failed with incorrect credentials as expected (HTTP 401).

--- Running Test 4: Rate Limiting ---
503
200
503
200
200
200
200
503
503
503
503
200
503
503
503
[PASS] Rate limiting test passed (service is still available).

--- Running Test 5: Prometheus Availability ---
[PASS] Prometheus is available (HTTP 200).

--- Running Test 6: Grafana Availability ---
[PASS] Grafana is available (HTTP 200).

All tests passed successfully!

```

## 6. rétrospective des actions vis à vis des attendus

1. nginx est bien le point d'entrée unique.

2. on a bien 3+1 respectivement pour les deux api v1 et v2

ubuntu@ip-172-31-37-17:~/mlops-nginx-exam-2$ docker container ls
CONTAINER ID   IMAGE                                    COMMAND                  CREATED          STATUS                    PORTS                                                                                                                           NAMES
983caeb39645   grafana/grafana:latest                   "/run.sh"                34 minutes ago   Up 34 minutes             0.0.0.0:3000->3000/tcp, [::]:3000->3000/tcp                                                                                     grafana_dashboard
63496df6ed81   prom/prometheus:latest                   "/bin/prometheus --c…"   34 minutes ago   Up 34 minutes             0.0.0.0:9090->9090/tcp, [::]:9090->9090/tcp                                                                                     prometheus_server
1f7f409ee01b   nginx/nginx-prometheus-exporter:latest   "/usr/bin/nginx-prom…"   34 minutes ago   Up 34 minutes             0.0.0.0:9113->9113/tcp, [::]:9113->9113/tcp                                                                                     nginx_exporter
d2821f25161c   mlopsv-nginx                             "/docker-entrypoint.…"   34 minutes ago   Up 34 minutes             0.0.0.0:443->443/tcp, [::]:443->443/tcp, 0.0.0.0:8081->8081/tcp, [::]:8081->8081/tcp, 0.0.0.0:8080->80/tcp, [::]:8080->80/tcp   nginx_revproxy
ba348c5a837b   mlopsv-mlops-api-v1                      "uvicorn main:app --…"   34 minutes ago   Up 34 minutes (healthy)   8001/tcp                                                                                                                        mlopsv-mlops-api-v1-3
c45a736192f6   mlopsv-mlops-api-v1                      "uvicorn main:app --…"   34 minutes ago   Up 34 minutes (healthy)   8001/tcp                                                                                                                        mlopsv-mlops-api-v1-2
9b805ef794ba   mlopsv-mlops-api-v1                      "uvicorn main:app --…"   34 minutes ago   Up 34 minutes (healthy)   8001/tcp                                                                                                                        mlopsv-mlops-api-v1-1
6aa79d2e1e8d   mlopsv-mlops-api-v2                      "uvicorn main:app --…"   34 minutes ago   Up 34 minutes (healthy)   8002/tcp                                                                                                                        mlopsv-mlops-api-v2-1
ubuntu@ip-172-31-37-17:~/mlops-nginx-exam-2$ 

3. la com passe par https avec les configs ssl TSL en place

4. la gestion de l'authentication grace au certificat et au htpasswd est en place

5. l'alternance de 200/503 montre le gestion des limites contre les DDOS

6. le test montre la réalisation de l'AB testing correcte

7. on voit prometheus et grafan en place et répondant.



## 7. et enfin de l'usage des ressources avec la conteneurisation
l'espace disque occupé par les dockers peut être préoccupant, surtout sur des vm contrainte n'ayant pas accés à de large file système
Mais pas que, des containers trop copieux vont réduire les capacités de develepoment.
(Les dockers sont représentés par des Baleines et on préfèrerait des dauphins ...)

On ne se rend pas compte des GB qui peuvent filé si on manipule des images trop grosse.

- loader Torch pour deux backend cpu et gpu et c'est 2GB d'embarqué - Torch avec NVidia c'est énorme - pratique, mais gros.

- Gérer proprement la layerisation - l'empillement des couches peut éviter, en nétoyer des builds intermédiaires, d'accumuler des ressources inutiles.
assez simplement, si la chose fabriqué est petites, pas de problème pour passer son chemin, par contre si c'est volumineux, la y a matière à regarder.

- uv est rapide, mais c'est au prix de 2 a trois 3Gb de couche de cache local qu'il est possible aussi d'adroitement éviter de loader dans ces dockers images

  ref: ce chore/cpugpu en cours de PR https://github.com/schmilblick-ai/Supply-Chain-MLOps/blob/chore/cpugpu/Dockerfile
  (un chore est une feature corvée dans la git|github pop culture)


  Dans ce Dockerfile étrange, on a l'impression de faire les choses en double, mais en fait l'empillement des couches
  et le déport du cache uv or image, amène stratégiquement à la réduction de la taille de l'image par un facteur X4, 

- maitriser la taille de ses images docker peut être un avantage pour pouvoir se déployer sur de plus petite ressource et être écoresponsable.

- on a vite fait de surconsomé

Aussi je résume mes commandes préféré pour la frugalité:

df en nativ va permettre d'observer sur une machine les mounts points possible et leur capacités disque
disque local ,disque externe, disque de différente nature et vitessen d'entrée sortie, SSD, 
montage varié, en NFS ou en disque partagé à travers cluster de machine
ou montage sur repository externe, les architectures sont variées.

du coup docker aussi à sont df

```bash
ubuntu@ip-172-31-37-17:~/mlops-nginx-exam-2$ df -Ph .
Filesystem       Size  Used Avail Use% Mounted on
/dev/root         29G   17G   12G  61% /

ubuntu@ip-172-31-37-17:~/mlops-nginx-exam-2$ docker system df
TYPE            TOTAL     ACTIVE    SIZE      RECLAIMABLE
Images          33        6         2.659GB   1.154GB (43%)
Containers      8         8         5.37MB    0B (0%)
Local Volumes   4         2         109.5MB   55.19MB (50%)
Build Cache     77        0         714.3kB   714.3kB

ubuntu@ip-172-31-37-17:~/mlops-nginx-exam-2$ docker image ls
<none>                            <none>    c70b8df252df   10 hours ago     161MB
mlops-mlops-iris-api              latest    71456008d64e   11 hours ago     409MB
<none>                            <none>    1558940b6daa   11 hours ago     161MB
<none>                            <none>    4f6ebdf37934   12 hours ago     161MB
<none>                            <none>    905214339a95   12 hours ago     161MB
<none>                            <none>    6501e658e267   12 hours ago     161MB
<none>                            <none>    48e6a2c6fa27   12 hours ago     161MB
<none>                            <none>    f91e8549c165   12 hours ago     161MB
<none>                            <none>    ea6ef64333b1   12 hours ago     161MB
<none>                            <none>    eedd7d2476e0   16 hours ago     161MB
<none>                            <none>    bf500def79d1   17 hours ago     161MB
<none>                            <none>    c078a8cf65ab   17 hours ago     161MB
<none>                            <none>    4da1464b0e9f   23 hours ago     161MB
<none>                            <none>    3d5833ec6dc1   29 hours ago     409MB
<none>                            <none>    9797d0463911   29 hours ago     161MB
nginx                             latest    6f8edba05e38   37 hours ago     161MB
grafana/grafana                   latest    ffe38074db41   3 days ago       1.07GB
<none>                            <none>    d194154db848   3 days ago       161MB
mlops-iris-api                    latest    b6dcf33a9b26   4 days ago       409MB
<none>                            <none>    e11b47bbad18   4 days ago       409MB
prom/prometheus                   latest    eb76b4fb5776   2 weeks ago      423MB
nginx/nginx-prometheus-exporter   latest    0ba32d7c37e7   7 months ago     14.4MB

```

dans ce dernier listing on voit un tas d'image à <none> démultiplié
Il y a donc une fuite dans notre process de construction de buid qui
accumule c'est image zombie

J'ai cherché et ca porte le nom de "dangling" image (ou image pendue)

elle s'accumule à chaque fois qu'on relance un docker build sans --no-cache qui crée un historique de layers
docker build -t monapp:latest .   # l'ancienne "monapp:latest" devient <none>
docker build -t monapp:latest .   # rebelote
docker build -t monapp:latest .   # x50 fois...

si au lieu de mettre latest on tag une version, c'est résolu.

A voir à l'usage, après chaque build, un ```docker image -prune```

le pruning est cette opération de recyclage de l'espace disque

sur l'ensemble des assets listés plus haut
 - il y a ce qui est reclamable
 et ce qui est manifestement trop gros.

```bash

# Images non utilisées par un container actif (running OU stopped)
docker image prune -a
# Si tu veux aussi virer les containers stoppés en même temps
docker system prune -a
	-a = toutes les images inutilisées, pas seulement les <none>.
	Sans -a, seules les dangling images sont supprimées.

# ou bien
docker rmi $(docker images -q -f "dangling=true")

ubuntu@ip-172-31-37-17:~/mlops-nginx-exam-2$ docker image prune
WARNING! This will remove all dangling images.
Are you sure you want to continue? [y/N] y
Deleted Images:
deleted: sha256:4f6ebdf37934837959c59f3b19a962567874004168bd5e67fbf9d30627ccb660
deleted: sha256:dbbcb0b6a28278845b15e40ddffc1406a72b492b71267449066b50a0d8d11523
deleted: sha256:c70b8df252df5550a3a78e61736ca90d8225f166638903ae76c72624c147d7cc
deleted: sha256:e11b47bbad18ab05a7818baaaa139a4582e59ac12e9eaa96c4c67f35f9e78468
deleted: sha256:905214339a95dcbbecbb92589bfcde979967e78d8268f12526054add2cc6d761
deleted: sha256:4da1464b0e9f34ef9048ffbe2d556170229b20c9eb41b24da5f8140dc249585c

...
docker rmi $(docker images -q -f "dangling=true")
ubuntu@ip-172-31-37-17:~/mlops-nginx-exam-2$ docker image ls
REPOSITORY                        TAG       IMAGE ID       CREATED             SIZE
mlopsv-nginx                      latest    03566f5fd764   About an hour ago   161MB
mlopsv-mlops-api-v2               latest    cce768238b1f   About an hour ago   410MB
mlopsv-mlops-api-v1               latest    9b5c3ea43f2e   About an hour ago   410MB
mlops-api-v2                      latest    05e5b2e05aa5   3 hours ago         410MB
mlops-api-v1                      latest    5c79f13e9ebc   3 hours ago         410MB
mlops-nginx                       latest    d84066f85db3   8 hours ago         161MB
mlops-mlops-iris-api              latest    71456008d64e   12 hours ago        409MB
nginx                             latest    6f8edba05e38   38 hours ago        161MB
grafana/grafana                   latest    ffe38074db41   3 days ago          1.07GB
mlops-iris-api                    latest    b6dcf33a9b26   4 days ago          409MB
prom/prometheus                   latest    eb76b4fb5776   2 weeks ago         423MB
nginx/nginx-prometheus-exporter   latest    0ba32d7c37e7   7 months ago        14.4MB

```

merci pour votre attention !