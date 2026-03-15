docker run -dit --name db-apex-dev-container \
 -p 8080:8080 -p 1521:1521 \
 -v /dev/shm --tmpfs /dev/shm:rw,nosuid,nodev,exec,size=2g \
 db-apex-dev-image
