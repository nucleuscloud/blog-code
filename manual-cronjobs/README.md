# Manually Trigger and Run a Cronjob

## Manually invoke with Kubectl
```sh
kubectl apply -f cronjob.yaml
kubectl create job --from=cronjob/hello-world hello-world-01
```

## Manually invoke with Golang
```sh
go mod download
go run main.go
```

## Cleanup
```sh
$ kubectl delete cronjob hello-world
```
