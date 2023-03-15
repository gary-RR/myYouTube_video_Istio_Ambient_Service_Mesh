curl -L https://istio.io/downloadIstio | sh -

curl -L --remote-name-all https://gcsweb.istio.io/gcs/istio-build/dev/0.0.0-ambient.191fe680b52c1754ee72a06b3e0d3f9d116f2e82/istio-0.0.0-ambient.191fe680b52c1754ee72a06b3e0d3f9d116f2e82-linux-amd64.tar.gz{,.sha256sum}

tar xzvfC istio-0.0.0-ambient.191fe680b52c1754ee72a06b3e0d3f9d116f2e82-linux-amd64.tar.gz ./istio-1.17.1

sudo chown -R $(id -u):$(id -g) ./istio-1.17.1/istio-0.0.0-ambient.191fe680b52c1754ee72a06b3e0d3f9d116f2e82

chmod +rx ./istio-1.17.1/istio-0.0.0-ambient.191fe680b52c1754ee72a06b3e0d3f9d116f2e82/bin/istioctl
sudo cp ./istio-1.17.1/istio-0.0.0-ambient.191fe680b52c1754ee72a06b3e0d3f9d116f2e82/bin/istioctl /usr/local/bin

istioctl install --set profile=ambient

kubectl get pod -n istio-system

