docker run -p 5000:5000 -d --restart=always --name registry     -e REGISTRY_PROXY_REMOTEURL=http://registry-1.docker.io   -v /opt/shared/docker_registry_cache:/var/lib/registry   registry:2
