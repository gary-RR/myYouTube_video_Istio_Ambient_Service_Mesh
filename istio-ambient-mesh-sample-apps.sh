ISTIO_DIR="./istio-1.17.1"

#Install sample app
kubectl apply -f $ISTIO_DIR/samples/bookinfo/platform/kube/bookinfo.yaml
kubectl apply -f https://raw.githubusercontent.com/linsun/sample-apps/main/sleep/sleep.yaml
kubectl apply -f https://raw.githubusercontent.com/linsun/sample-apps/main/sleep/notsleep.yaml
#Creat virtual service to enable access from outside the cluster
kubectl apply -f ./istio-1.17.1/samples/bookinfo/networking/bookinfo-gateway.yaml

#Set the INGRESS_HOST and INGRESS_PORT variables for accessing the gateway
INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}')
INGRESS_HOST=$(kubectl get po -l istio=ingressgateway -n istio-system -o jsonpath='{.items[0].status.hostIP}')
#GATEWAY_URL
GATEWAY_URL=$INGRESS_HOST:$INGRESS_PORT
#Ensure an IP address and port were successfully assigned to the environment variable
echo "$GATEWAY_URL"

#Get the name of a productpage pod
PORDUCTPAGE_POD_NAME=$(kubectl get pods -no-headers -n default | awk '{ print $1}' | grep productpage)

#Check for side car
kubectl get pods $PORDUCTPAGE_POD_NAME -n default  -o jsonpath='{.spec.containers[*].name}*'

#####****** Show ztunnle logs *****************************

#Test the service through the gayeway
kubectl exec deploy/sleep -- curl -s http://$GATEWAY_URL/productpage | head -n1

kubectl exec deploy/sleep -- curl -s http://productpage:9080/ | head -n1
kubectl exec deploy/notsleep -- curl -s http://productpage:9080/ | head -n1

#Enable the ambient mesh
kubectl label namespace default istio.io/dataplane-mode=ambient

#Observe the new "ambient" mode label
kubectl describe ns default

#Test services again with ztunnles active and check logs
kubectl exec deploy/sleep -- curl -s http://productpage:9080/ | head -n1
kubectl exec deploy/notsleep -- curl -s http://productpage:9080/ | head -n1

#L4 Authorization Policies
#Explicitly allow the sleep service account and istio-ingressgateway service accounts to call the productpage service:
kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
 name: productpage-viewer
 namespace: default
spec:
 selector:
   matchLabels:
     app: productpage
 action: ALLOW
 rules:
 - from:
   - source:
       principals: ["cluster.local/ns/default/sa/sleep", "cluster.local/ns/istio-system/sa/istio-ingressgateway-service-account"]
EOF

#Confirm the above authorization policy is working
# this should succeed
kubectl exec deploy/sleep -- curl -s http://istio-ingressgateway.istio-system/productpage | head -n1
# this should succeed
kubectl exec deploy/sleep -- curl -s http://productpage:9080/ | head -n1
# this should fail with an empty reply
kubectl exec deploy/notsleep -- curl -s http://productpage:9080/ | head -n1

#Display pods in the default name space before dploying a waypoint proxy
kubectl get pods -o wide

# L7 authorization policy
# Using the Kubernetes Gateway API, you can deploy a waypoint proxy for the productpage service that uses the 
# bookinfo-productpage service account. Any traffic going to the productpage service will be mediated, enforced and observed by the Layer 7 (L7) proxy.
# **Note the gatewayClassName has to be istio-mesh for the waypoint proxy.
kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1alpha2
kind: Gateway
metadata:
 name: productpage
 annotations:
   istio.io/service-account: bookinfo-productpage
spec:
 gatewayClassName: istio-mesh
EOF

#Display pods in the default name space after dploying the waypoint proxy
kubectl get pods -o wide

# View the productpage waypoint proxy status; you should see the details of the gateway resource with Ready status
kubectl get gateway productpage -o yaml


# Update our AuthorizationPolicy to explicitly allow the sleep service account and istio-ingressgateway service accounts 
# to GET the productpage service, but perform no other operations
kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
 name: productpage-viewer
 namespace: default
spec:
 selector:
   matchLabels:
     app: productpage
 action: ALLOW
 rules:
 - from:
   - source:
       principals: ["cluster.local/ns/default/sa/sleep", "cluster.local/ns/istio-system/sa/istio-ingressgateway-service-account"]
   to:
   - operation:
       methods: ["GET"]
EOF

#Confirm the above authorization policy is working
# this should fail with an RBAC error because it is not a GET operation
kubectl exec deploy/sleep -- curl -s http://productpage:9080/ -X DELETE | head -n1
# this should fail with an RBAC error because the identity is not allowed
kubectl exec deploy/notsleep -- curl -s http://productpage:9080/  | head -n1
# this should continue to work
kubectl exec deploy/sleep -- curl -s http://productpage:9080/ | head -n1


# With the productpage waypoint proxy deployed, you’ll also automatically get L7 metrics for all requests to the productpage service
# Lets examine access denied (403) traffic:
kubectl exec deploy/bookinfo-productpage-waypoint-proxy -- curl -s http://localhost:15020/stats/prometheus | grep istio_requests_total | grep 403


# Control Traffic
# Deploy a waypoint proxy for the review service, using the bookinfo-review service account, so that any traffic going to the 
# review service will be mediated by the waypoint proxy.
kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1alpha2
kind: Gateway
metadata:
 name: reviews
 annotations:
   istio.io/service-account: bookinfo-reviews
spec:
 gatewayClassName: istio-mesh
EOF

kubectl get pods

# Apply the reviews virtual service to control 90% traffic to reviews v1 and 10% traffic to reviews v2.
kubectl apply -f $ISTIO_DIR/samples/bookinfo/networking/virtual-service-reviews-90-10.yaml
kubectl apply -f $ISTIO_DIR/samples/bookinfo/networking/destination-rule-reviews.yaml

#Confirm that roughly 10% traffic from the 100 requests go to reviews-v2
kubectl exec -it deploy/sleep -- sh -c 'for i in $(seq 1 100); do curl -s http://istio-ingressgateway.istio-system/productpage | grep reviews-v.-; done'


#*****Cleanup***********************************************************************
#Remove istio
istioctl uninstall -y --purge && kubectl delete ns istio-system

#Remove sample apps
kubectl label namespace default istio.io/dataplane-mode-
kubectl delete -f ./istio-1.17.1/samples/bookinfo/platform/kube/bookinfo.yaml
kubectl delete -f https://raw.githubusercontent.com/linsun/sample-apps/main/sleep/sleep.yaml
kubectl delete -f https://raw.githubusercontent.com/linsun/sample-apps/main/sleep/notsleep.yaml
kubectl delete -f ./istio-1.17.1/samples/bookinfo/networking/bookinfo-gateway.yaml
kubectl delete AuthorizationPolicy productpage-viewer
kubectl delete gateway productpage
kubectl delete VirtualService reviews
kubectl delete DestinationRule reviews
kubectl delete gateway reviews
