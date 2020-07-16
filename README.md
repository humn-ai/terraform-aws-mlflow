# terraform-aws-mlflow


## Roadmap

- [x] Example usage folder (gitignored)
- [x] ECS cluster and service (backed by local storage)
- [x] Output info to hook it to an LB listener
- [x] Default S3 bucket + IAM role + Documentation
- [x] RDS cluster + backend-store-uri + Documentation
- [ ] Full example with a custom domain, ALB and S3 buckets
- [ ] Terratest and GitHub Actions
- [ ] Terraform fmt and grooming
- [ ] README
- [ ] LICENSE
- [ ] PR to mlflow to accept BACKEND_STORE_URI as an environment variable => Allow selecting a different container image
- [ ] Target-based autoscaling
- [ ] Allow injecting sidecar containers and inject a datadog agent


## Caveats / Notes

* This module only supports [this docker image](https://hub.docker.com/r/larribas/mlflow). The reason behind this is that we need to inject the database password as a secret environment variable, which can only be injected into the ECS task definition by overriding the entrypoint and making a lot of assumptions about how the base image was built.
* By default, the load balancer is internal. This is because as of v1.9.1, MLFlow doesn't have native authentication or authorization. We recommend exposing MLFlow behind a VPN or using OIDC/Cognito together with the LB listener.

