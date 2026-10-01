# Golden Owl DevOps Internship Challenge

## English

### Overview

This repository contains a Node.js API deployed to AWS ECS Fargate. GitHub Actions runs CI/CD, Amazon ECR stores container images, and Terraform provisions **all AWS infrastructure**; no infrastructure resources need to be created manually in the AWS Console. The application runs behind an HTTPS Application Load Balancer (ALB) with ECS Service Auto Scaling and alarm-based deployment rollback. The domain and its DNS records are managed separately at VinaHost.

### Repository structure

```text
.
├── .github/workflows/ci.yaml   # CI/CD: tests, SonarQube, Trivy, ECR, ECS
├── Dockerfile                  # Multi-stage, non-root container image
├── src/                        # Node.js API and unit tests
├── terraform/
│   ├── bootstrap/
│   │   └── main.tf             # S3 state bucket and ECR repository
│   └── app/
│       ├── main.tf             # VPC, ALB/HTTPS, ACM, ECS, alarms, scaling
│       ├── iam.tf              # IAM roles and GitHub OIDC trust
│       └── outputs.tf          # HTTPS URL, ACM DNS record, identifiers
└── docs/evidence/              # Architecture diagram and AWS screenshots
```

Apply `terraform/bootstrap` first, publish the initial `bootstrap` image to ECR, and then apply `terraform/app`.

### Results

| Item | Result |
| --- | --- |
| Source code | [Public GitHub repository](https://github.com/huymt05/goldenowl-devops-internship-challenge) |
| Deployed application | [HTTPS application endpoint](https://app.huymt05-goldenowlchallenge.io.vn/) |
| API response | `{"message":"Welcome warriors to Golden Owl!"}` (verified over HTTPS) |
| HTTPS | ACM certificate issued; HTTP port 80 redirects to HTTPS port 443 with `301` |
| Verified CI/CD deployment | [Master workflow run #18](https://github.com/huymt05/goldenowl-devops-internship-challenge/actions/runs/36830578185): quality, image scan, and deploy succeeded |
| Final container image size | 53,650,757 bytes (~53.7 MB / 51.2 MiB), reported by ECR for image tag `f2d2f8cbf431114e00a06407988aa25a22620a4c` |
| AWS region | `ap-southeast-1` (Singapore) |

The application returns JSON; it has no frontend. Test the public endpoint with:

```bash
curl -i https://app.huymt05-goldenowlchallenge.io.vn/
curl -I http://app.huymt05-goldenowlchallenge.io.vn/
```

### Visual flow diagram

![CI/CD workflow and AWS architecture](docs/evidence/architecture.png)

The diagram shows the original CI/CD and AWS deployment flow. It predates the HTTPS and automatic-rollback additions; the architecture section below describes the current deployment. The [deployment screenshots](#deployment-evidence) provide supporting evidence.

### CI/CD pipeline

The workflow is defined in [`.github/workflows/ci.yaml`](.github/workflows/ci.yaml).

| Event | Unit tests | SonarQube Cloud | Docker build + Trivy | Push to ECR + deploy to ECS |
| --- | --- | --- | --- | --- |
| Push to `feature/**` | Yes | Skipped | Yes | No |
| Pull request to `master` | Yes | Yes | Yes | No |
| Push to `master` | Yes | Yes | Yes | Yes, after the checks pass |

The unit-test job runs `npm ci` and Jest with coverage. The image job runs only after the quality job succeeds; publishing to ECR and deployment are restricted to pushes on `master`.

Trivy fails the image job for fixable `HIGH` or `CRITICAL` vulnerabilities. Released images are tagged with the Git commit SHA. For deployment, GitHub Actions assumes an AWS IAM role through OIDC, renders a new ECS task definition, updates the ECS service, and waits for stability. No long-lived AWS access keys are stored in GitHub.

ECS uses its **native canary strategy**: 10% of traffic goes to the new revision for 5 minutes, then traffic moves to 100%, followed by a 5-minute bake period. CloudWatch alarms watch target-group 5xx responses; an alarm during deployment triggers ECS rollback. This deployment does not use Argo CD or AWS CodeDeploy.

Configure these GitHub Actions repository **variables**: `AWS_ROLE_ARN`, `AWS_REGION`, `ECR_REPOSITORY`, `ECS_CLUSTER`, `ECS_SERVICE`, `ECS_TASK_FAMILY`, and `ECS_CONTAINER_NAME`. Store `SONAR_TOKEN` as a repository **secret**. Do not commit credentials or tokens.

### AWS architecture and Terraform

All AWS infrastructure is defined and provisioned with Terraform; nothing needs to be created manually through the AWS Console.

- [`terraform/bootstrap`](terraform/bootstrap/main.tf) creates a versioned, encrypted S3 bucket for Terraform state and an ECR repository with immutable image tags.
- [`terraform/app`](terraform/app/main.tf) creates the VPC, two public subnets in separate Availability Zones, security groups, internet-facing ALB, two target groups, ECS Fargate service, ACM certificate, CloudWatch log group and 5xx alarms, IAM roles, GitHub OIDC provider, and ECS Service Auto Scaling.

VinaHost DNS maps `app.huymt05-goldenowlchallenge.io.vn` to the ALB and hosts the ACM validation CNAME. The ALB terminates TLS with the ACM certificate on port **443**; port **80** returns a `301` redirect to HTTPS. ALB-to-task traffic remains HTTP on port **3000**, accessible only from the ALB security group. The ECS service starts with **2 tasks** and scales between **2 and 4 tasks**, targeting **60% average CPU utilization**. Tasks send application logs to `/ecs/goldenowl-app`, retained for 7 days. Blue and green target-group alarms enter `ALARM` after at least **3 target 5xx responses in each of two consecutive 60-second periods**; ECS is configured to roll back an affected deployment. Missing metrics from an idle target group do not trigger the alarm.

#### Provisioning a fresh environment

Prerequisites: Terraform >= 1.10, Docker, AWS CLI, and AWS credentials with permission to provision the listed resources. Node.js 24 and npm are needed to run the application locally.

These commands are for a **new deployment**. The Terraform S3 backend, ECR name, AWS region, domain, and GitHub OIDC trust subject are specific to this account and fork; update them before reuse. Preserve the bootstrap Terraform state: applying from another checkout without that state can conflict with existing resources. Register a domain with authoritative DNS access; VinaHost DNS records are managed outside Terraform.

```powershell
terraform -chdir=terraform/bootstrap init
terraform -chdir=terraform/bootstrap apply

$ecr = terraform -chdir=terraform/bootstrap output -raw ecr_repository_url
$registry = $ecr.Split('/')[0]
aws ecr get-login-password --region ap-southeast-1 | docker login --username AWS --password-stdin $registry
docker build -t goldenowl-app:bootstrap .
docker tag goldenowl-app:bootstrap "${ecr}:bootstrap"
docker push "${ecr}:bootstrap"

terraform -chdir=terraform/app init
terraform -chdir=terraform/app plan '-target=aws_acm_certificate.app' -out acm.tfplan
terraform -chdir=terraform/app apply acm.tfplan
terraform -chdir=terraform/app output acm_validation_record
```

Add the returned ACM validation CNAME to the authoritative DNS zone and wait until the certificate status is `ISSUED`. Then review and apply the full plan:

```powershell
$certArn = terraform -chdir=terraform/app output -raw acm_certificate_arn
aws acm describe-certificate --region ap-southeast-1 --certificate-arn $certArn --query 'Certificate.Status' --output text
terraform -chdir=terraform/app plan -out https.tfplan
terraform -chdir=terraform/app show https.tfplan
terraform -chdir=terraform/app apply https.tfplan
terraform -chdir=terraform/app output alb_dns_name
terraform -chdir=terraform/app output deployment_url
```

Do **not** run the full apply until ACM reports `ISSUED`. Once the ALB exists, add an `app` CNAME pointing to the `alb_dns_name` output in VinaHost DNS. The initial ECS task definition references the ECR `bootstrap` image. Later releases are built and deployed by GitHub Actions. Running AWS resources incur charges.

### Docker image

The [Dockerfile](Dockerfile) uses a multi-stage build. The `node:24-alpine3.24` build stage installs only production dependencies with `npm ci --omit=dev`. The final `alpine:3.24` stage copies the Node.js binary, application code, and production dependencies, but **does not include npm**. It runs as non-root UID/GID `1000:1000`, with `dumb-init` forwarding process signals. [`.dockerignore`](.dockerignore) excludes files unnecessary for the build.

The size above is the ECR-reported image size for the deployed commit, not the local uncompressed size shown by `docker images`. Recheck it with `aws ecr describe-images --region ap-southeast-1 --repository-name goldenowl-app --image-ids imageTag=f2d2f8cbf431114e00a06407988aa25a22620a4c --query "imageDetails[0].imageSizeInBytes" --output text`.

### Run locally

```bash
cd src
npm ci
npm test
npm start
```

Open `http://localhost:3000/` or run `curl http://localhost:3000/`. To run the container from the repository root:

```bash
docker build -t goldenowl-app:local .
docker run --rm -p 3000:3000 goldenowl-app:local
```

### Deployment evidence

These screenshots show the configured AWS resources; they do not replace the required manually drawn diagram.

- [ECS native canary deployment: 10%, 5 minutes](docs/evidence/ecs-canary.png)
- [Active ECS Auto Scaling policy: 2–4 tasks, CPU 60%](docs/evidence/auto-scaling.png)
- [Active internet-facing Application Load Balancer](docs/evidence/alb-loadbalancer.png)

The manually drawn architecture image above does not yet show the ACM certificate, HTTP-to-HTTPS redirect, or CloudWatch-alarm rollback. Update that image separately if it must represent the current bonus features.

---

## Tiếng Việt

### Tổng quan

Repo này chứa API Node.js được triển khai trên AWS ECS Fargate. GitHub Actions thực hiện CI/CD, Amazon ECR lưu Docker image, còn Terraform cấp phát **toàn bộ hạ tầng AWS**; không cần tạo tài nguyên hạ tầng thủ công qua AWS Console. Ứng dụng chạy sau Application Load Balancer (ALB) có HTTPS, ECS Service Auto Scaling và cơ chế rollback triển khai dựa trên cảnh báo. Tên miền và bản ghi DNS được quản lý riêng tại VinaHost.

### Cấu trúc repository

```text
.
├── .github/workflows/ci.yaml   # CI/CD: test, SonarQube, Trivy, ECR, ECS
├── Dockerfile                  # Image nhiều giai đoạn, chạy non-root
├── src/                        # API Node.js và unit test
├── terraform/
│   ├── bootstrap/
│   │   └── main.tf             # S3 bucket lưu state và ECR repository
│   └── app/
│       ├── main.tf             # VPC, ALB/HTTPS, ACM, ECS, alarm, scaling
│       ├── iam.tf              # IAM role và quan hệ tin cậy GitHub OIDC
│       └── outputs.tf          # URL HTTPS, bản ghi ACM, thông tin deploy
└── docs/evidence/              # Sơ đồ kiến trúc và ảnh minh chứng AWS
```

Áp dụng `terraform/bootstrap` trước, đẩy image `bootstrap` đầu tiên lên ECR, rồi mới áp dụng `terraform/app`.

### Kết quả

| Hạng mục | Kết quả |
| --- | --- |
| Mã nguồn | [GitHub repository công khai](https://github.com/huymt05/goldenowl-devops-internship-challenge) |
| Ứng dụng đã triển khai | [Endpoint HTTPS](https://app.huymt05-goldenowlchallenge.io.vn/) |
| Phản hồi API | `{"message":"Welcome warriors to Golden Owl!"}` (đã kiểm tra qua HTTPS) |
| HTTPS | Chứng chỉ ACM đã cấp; HTTP cổng 80 chuyển sang HTTPS cổng 443 bằng mã `301` |
| CI/CD và triển khai đã xác nhận | [Workflow #18 trên master](https://github.com/huymt05/goldenowl-devops-internship-challenge/actions/runs/36830578185): kiểm tra chất lượng, quét image và deploy đều thành công |
| Kích thước container image cuối cùng | 53.650.757 byte (~53,7 MB / 51,2 MiB), do ECR báo cho image tag `f2d2f8cbf431114e00a06407988aa25a22620a4c` |
| Khu vực AWS | `ap-southeast-1` (Singapore) |

Ứng dụng trả về JSON và không có frontend. Kiểm tra endpoint công khai bằng lệnh:

```bash
curl -i https://app.huymt05-goldenowlchallenge.io.vn/
curl -I http://app.huymt05-goldenowlchallenge.io.vn/
```

### Sơ đồ quy trình và kiến trúc

![Sơ đồ quy trình CI/CD và kiến trúc AWS](docs/evidence/architecture.png)

Sơ đồ thể hiện quy trình CI/CD và kiến trúc AWS ban đầu. Ảnh này được vẽ trước khi bổ sung HTTPS và rollback tự động; phần kiến trúc bên dưới mô tả trạng thái hiện tại. Các [ảnh minh chứng](#ảnh-minh-chứng-triển-khai) là bằng chứng bổ sung.

### Quy trình CI/CD

Workflow nằm trong [`.github/workflows/ci.yaml`](.github/workflows/ci.yaml).

| Sự kiện | Unit test | SonarQube Cloud | Docker build + Trivy | Đẩy lên ECR + triển khai ECS |
| --- | --- | --- | --- | --- |
| Push lên `feature/**` | Có | Bỏ qua | Có | Không |
| Pull request vào `master` | Có | Có | Có | Không |
| Push lên `master` | Có | Có | Có | Có, sau khi các bước kiểm tra đạt |

Job unit test chạy `npm ci` và Jest kèm coverage. Job image chỉ chạy khi job kiểm tra chất lượng thành công; bước đẩy image lên ECR và triển khai chỉ chạy khi push lên `master`.

Trivy làm job image thất bại nếu phát hiện lỗ hổng `HIGH` hoặc `CRITICAL` đã có bản sửa. Image phát hành được gắn tag theo Git commit SHA. Khi triển khai, GitHub Actions dùng OIDC để nhận quyền IAM trên AWS, tạo phiên bản ECS task definition mới, cập nhật ECS service và chờ service ổn định. GitHub không lưu AWS access key dài hạn.

ECS dùng **chiến lược canary có sẵn**: chuyển 10% lưu lượng sang phiên bản mới trong 5 phút, sau đó chuyển 100% và tiếp tục theo dõi thêm 5 phút. CloudWatch alarm theo dõi phản hồi 5xx của các target group; nếu alarm kích hoạt trong lúc triển khai, ECS sẽ rollback. Hệ thống không dùng Argo CD hay AWS CodeDeploy.

Cấu hình các **variables** sau trong GitHub Actions: `AWS_ROLE_ARN`, `AWS_REGION`, `ECR_REPOSITORY`, `ECS_CLUSTER`, `ECS_SERVICE`, `ECS_TASK_FAMILY`, `ECS_CONTAINER_NAME`. Lưu `SONAR_TOKEN` dưới dạng **secret**. Không commit thông tin đăng nhập hoặc token.

### Kiến trúc AWS và Terraform

Toàn bộ hạ tầng AWS được định nghĩa và cấp phát bằng Terraform; không cần tạo tài nguyên thủ công qua AWS Console.

- [`terraform/bootstrap`](terraform/bootstrap/main.tf) tạo S3 bucket lưu Terraform state có versioning và mã hóa, cùng ECR repository có image tag bất biến.
- [`terraform/app`](terraform/app/main.tf) tạo VPC, hai public subnet ở hai Availability Zone, security group, ALB công khai, hai target group, ECS Fargate service, chứng chỉ ACM, CloudWatch log group và alarm 5xx, IAM role, GitHub OIDC provider và ECS Service Auto Scaling.

DNS tại VinaHost ánh xạ `app.huymt05-goldenowlchallenge.io.vn` đến ALB và lưu CNAME để xác thực chứng chỉ ACM. ALB kết thúc TLS bằng chứng chỉ ACM ở cổng **443**; cổng **80** trả `301` chuyển sang HTTPS. Kết nối từ ALB đến task vẫn dùng HTTP ở cổng **3000**, chỉ cho phép từ security group của ALB. ECS service khởi chạy với **2 task** và tự điều chỉnh trong khoảng **2–4 task**, theo mục tiêu **CPU trung bình 60%**. Các task gửi log ứng dụng tới `/ecs/goldenowl-app`; log được lưu 7 ngày. Alarm của hai target group xanh dương/xanh lá chuyển sang trạng thái `ALARM` khi có ít nhất **3 phản hồi 5xx ở mỗi chu kỳ 60 giây trong hai chu kỳ liên tiếp**; ECS được cấu hình rollback đợt triển khai bị ảnh hưởng. Target group không có lưu lượng sẽ không kích hoạt alarm do thiếu metric.

#### Cấp phát môi trường mới

Yêu cầu: Terraform >= 1.10, Docker, AWS CLI và AWS credentials có quyền tạo các tài nguyên nêu trên. Cần Node.js 24 và npm nếu muốn chạy ứng dụng trên máy cá nhân.

Các lệnh sau dành cho **lần triển khai mới**. S3 backend, tên ECR, AWS region, tên miền và điều kiện tin cậy GitHub OIDC trong Terraform đang gắn với tài khoản và fork này; hãy sửa trước khi dùng lại. Cần giữ Terraform state của bootstrap: chạy từ bản clone khác mà không có state có thể xung đột với tài nguyên đã tạo. Cần đăng ký tên miền và có quyền sửa DNS zone đang có hiệu lực; bản ghi DNS tại VinaHost được quản lý ngoài Terraform.

```powershell
terraform -chdir=terraform/bootstrap init
terraform -chdir=terraform/bootstrap apply

$ecr = terraform -chdir=terraform/bootstrap output -raw ecr_repository_url
$registry = $ecr.Split('/')[0]
aws ecr get-login-password --region ap-southeast-1 | docker login --username AWS --password-stdin $registry
docker build -t goldenowl-app:bootstrap .
docker tag goldenowl-app:bootstrap "${ecr}:bootstrap"
docker push "${ecr}:bootstrap"

terraform -chdir=terraform/app init
terraform -chdir=terraform/app plan '-target=aws_acm_certificate.app' -out acm.tfplan
terraform -chdir=terraform/app apply acm.tfplan
terraform -chdir=terraform/app output acm_validation_record
```

Thêm CNAME xác thực ACM vừa nhận vào DNS zone đang có hiệu lực và chờ chứng chỉ chuyển sang `ISSUED`. Sau đó xem kỹ plan đầy đủ rồi áp dụng:

```powershell
$certArn = terraform -chdir=terraform/app output -raw acm_certificate_arn
aws acm describe-certificate --region ap-southeast-1 --certificate-arn $certArn --query 'Certificate.Status' --output text
terraform -chdir=terraform/app plan -out https.tfplan
terraform -chdir=terraform/app show https.tfplan
terraform -chdir=terraform/app apply https.tfplan
terraform -chdir=terraform/app output alb_dns_name
terraform -chdir=terraform/app output deployment_url
```

**Không** chạy full apply khi ACM chưa báo `ISSUED`. Sau khi ALB được tạo, thêm CNAME `app` tại VinaHost trỏ đến giá trị `alb_dns_name` vừa nhận. ECS task definition ban đầu dùng image `bootstrap` trên ECR. Các bản phát hành tiếp theo do GitHub Actions build và triển khai. Tài nguyên AWS có thể phát sinh chi phí trong thời gian hoạt động.

### Docker image

[Dockerfile](Dockerfile) dùng multi-stage build. Giai đoạn `node:24-alpine3.24` chỉ cài production dependencies bằng `npm ci --omit=dev`. Giai đoạn chạy cuối cùng dùng `alpine:3.24`, chỉ sao chép Node.js binary, mã nguồn và production dependencies, **không mang theo npm**. Container chạy non-root với UID/GID `1000:1000`; `dumb-init` chuyển tiếp tín hiệu cho tiến trình. [`.dockerignore`](.dockerignore) loại các file không cần thiết khỏi build context.

Kích thước ở trên là số ECR báo cho image của commit đã triển khai, không phải kích thước image chưa nén trên máy do `docker images` hiển thị. Có thể kiểm tra lại bằng lệnh `aws ecr describe-images --region ap-southeast-1 --repository-name goldenowl-app --image-ids imageTag=f2d2f8cbf431114e00a06407988aa25a22620a4c --query "imageDetails[0].imageSizeInBytes" --output text`.

### Chạy cục bộ

```bash
cd src
npm ci
npm test
npm start
```

Mở `http://localhost:3000/` hoặc chạy `curl http://localhost:3000/`. Để chạy container từ thư mục gốc của repo:

```bash
docker build -t goldenowl-app:local .
docker run --rm -p 3000:3000 goldenowl-app:local
```

### Ảnh minh chứng triển khai

Các ảnh sau minh chứng hạ tầng AWS đã được cấu hình; chúng không thay thế sơ đồ tự vẽ bắt buộc.

- [ECS native canary: 10% trong 5 phút](docs/evidence/ecs-canary.png)
- [ECS Auto Scaling hoạt động: 2–4 task, CPU 60%](docs/evidence/auto-scaling.png)
- [Application Load Balancer công khai và đang hoạt động](docs/evidence/alb-loadbalancer.png)

Ảnh kiến trúc tự vẽ phía trên chưa thể hiện chứng chỉ ACM, chuyển hướng HTTP sang HTTPS và rollback theo CloudWatch alarm. Cần cập nhật riêng ảnh đó nếu muốn sơ đồ phản ánh các tính năng bonus hiện tại.
