# Golden Owl DevOps Internship Challenge

## English

### Overview

This repository contains a Node.js API deployed to AWS ECS Fargate. GitHub Actions runs CI/CD, Amazon ECR stores container images, and Terraform provisions **all AWS infrastructure**; no infrastructure resources need to be created manually in the AWS Console. The application runs behind an Application Load Balancer (ALB) with ECS Service Auto Scaling.

### Repository structure

- `src/`: Node.js application and unit tests.
- `.github/workflows/ci.yaml`: CI/CD workflow.
- `terraform/bootstrap/`: Terraform state bucket and ECR repository.
- `terraform/app/`: Application infrastructure and GitHub OIDC role.
- `docs/evidence/`: architecture diagram and deployment screenshots.

### Results

| Item | Result |
| --- | --- |
| Source code | [Public GitHub repository](https://github.com/huymt05/goldenowl-devops-internship-challenge) |
| Deployed application | [AWS ALB endpoint](http://goldenowl-alb-1439674637.ap-southeast-1.elb.amazonaws.com/) |
| Expected response | `{"message":"Welcome warriors to Golden Owl!"}` |
| Final image size | **56,040,949 bytes (~56.0 MB)** reported by ECR; Docker Desktop reports **220 MB disk usage** locally |
| AWS region | `ap-southeast-1` (Singapore) |

The application returns JSON; it has no frontend. Test the public endpoint with:

```bash
curl http://goldenowl-alb-1439674637.ap-southeast-1.elb.amazonaws.com/
```

### Visual flow diagram

![CI/CD workflow and AWS architecture](docs/evidence/architecture.png)

The diagram shows both the CI/CD sequence and the deployed AWS architecture. The [deployment screenshots](#deployment-evidence) provide supporting evidence.

### CI/CD pipeline

The workflow is defined in [`.github/workflows/ci.yaml`](.github/workflows/ci.yaml).

| Event | Unit tests | SonarQube Cloud | Docker build + Trivy | Push to ECR + deploy to ECS |
| --- | --- | --- | --- | --- |
| Push to `feature/**` | Yes | Skipped | Yes | No |
| Pull request to `master` | Yes | Yes | Yes | No |
| Push to `master` | Yes | Yes | Yes | Yes, after the checks pass |

The unit-test job runs `npm ci` and Jest with coverage. The image job runs only after the quality job succeeds; publishing to ECR and deployment are restricted to pushes on `master`.

Trivy fails the image job for fixable `HIGH` or `CRITICAL` vulnerabilities. Released images are tagged with the Git commit SHA. For deployment, GitHub Actions assumes an AWS IAM role through OIDC, renders a new ECS task definition, updates the ECS service, and waits for stability. No long-lived AWS access keys are stored in GitHub.

ECS uses its **native canary strategy**: 10% of traffic goes to the new revision for 5 minutes, then traffic moves to 100%, followed by a 5-minute bake period. This deployment does not use Argo CD or AWS CodeDeploy.

Configure these GitHub Actions repository **variables**: `AWS_ROLE_ARN`, `AWS_REGION`, `ECR_REPOSITORY`, `ECS_CLUSTER`, `ECS_SERVICE`, `ECS_TASK_FAMILY`, and `ECS_CONTAINER_NAME`. Store `SONAR_TOKEN` as a repository **secret**. Do not commit credentials or tokens.

### AWS architecture and Terraform

All AWS infrastructure is defined and provisioned with Terraform; nothing needs to be created manually through the AWS Console.

- [`terraform/bootstrap`](terraform/bootstrap/main.tf) creates a versioned, encrypted S3 bucket for Terraform state and an ECR repository with immutable image tags.
- [`terraform/app`](terraform/app/main.tf) creates the VPC, two public subnets in separate Availability Zones, security groups, internet-facing ALB, two target groups, ECS Fargate service, CloudWatch log group, IAM roles, GitHub OIDC provider, and ECS Service Auto Scaling.

The ALB accepts HTTP on port 80. Only the ALB security group can access the application container on port 3000. The ECS service starts with **2 tasks** and scales between **2 and 4 tasks**, targeting **60% average CPU utilization**. Tasks send application logs to `/ecs/goldenowl-app`, retained for 7 days.

#### Provisioning a fresh environment

Prerequisites: Terraform >= 1.10, Docker, AWS CLI, and AWS credentials with permission to provision the listed resources. Node.js 24 and npm are needed to run the application locally.

These commands are for a **new deployment**. The Terraform S3 backend, ECR name, AWS region, and GitHub OIDC trust subject are specific to this account and fork; update them before reuse. Preserve the bootstrap Terraform state: applying from another checkout without that state can conflict with existing resources.

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
terraform -chdir=terraform/app apply
terraform -chdir=terraform/app output deployment_url
```

The initial ECS task definition references the ECR `bootstrap` image. Later releases are built and deployed by GitHub Actions. Running AWS resources incur charges.

### Docker image

The [Dockerfile](Dockerfile) uses a multi-stage build. Node.js 24 Alpine installs production dependencies with `npm ci --omit=dev`; a distroless Node.js 24 runtime runs the API as non-root user `65532`. [`.dockerignore`](.dockerignore) excludes files unnecessary for the build.

The published image measures **56,040,949 bytes (~56.0 MB) in ECR**. Docker Desktop reports **220 MB disk usage** for the local image; these are different size measurements.

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

**Limitations:** The ALB currently serves HTTP, not HTTPS. Automatic rollback is not configured.

---

## Tiếng Việt

### Tổng quan

Repo này chứa API Node.js được triển khai trên AWS ECS Fargate. GitHub Actions thực hiện CI/CD, Amazon ECR lưu Docker image, còn Terraform cấp phát **toàn bộ hạ tầng AWS**; không cần tạo tài nguyên hạ tầng thủ công qua AWS Console. Ứng dụng chạy sau Application Load Balancer (ALB) và có ECS Service Auto Scaling.

### Cấu trúc repository

- `src/`: ứng dụng Node.js và unit test.
- `.github/workflows/ci.yaml`: workflow CI/CD.
- `terraform/bootstrap/`: S3 bucket lưu Terraform state và ECR repository.
- `terraform/app/`: hạ tầng ứng dụng và IAM role cho GitHub OIDC.
- `docs/evidence/`: sơ đồ kiến trúc và ảnh minh chứng triển khai.

### Kết quả

| Hạng mục | Kết quả |
| --- | --- |
| Mã nguồn | [GitHub repository công khai](https://github.com/huymt05/goldenowl-devops-internship-challenge) |
| Ứng dụng đã triển khai | [Truy cập qua AWS ALB](http://goldenowl-alb-1439674637.ap-southeast-1.elb.amazonaws.com/) |
| Phản hồi mong đợi | `{"message":"Welcome warriors to Golden Owl!"}` |
| Kích thước image cuối cùng | **56.040.949 byte (~56,0 MB)** theo ECR; Docker Desktop hiển thị **220 MB dung lượng đĩa** ở máy cục bộ |
| Khu vực AWS | `ap-southeast-1` (Singapore) |

Ứng dụng trả về JSON và không có frontend. Kiểm tra endpoint công khai bằng lệnh:

```bash
curl http://goldenowl-alb-1439674637.ap-southeast-1.elb.amazonaws.com/
```

### Sơ đồ quy trình và kiến trúc

![Sơ đồ quy trình CI/CD và kiến trúc AWS](docs/evidence/architecture.png)

Sơ đồ thể hiện cả quy trình CI/CD lẫn kiến trúc AWS đã triển khai. Các [ảnh minh chứng](#ảnh-minh-chứng-triển-khai) là bằng chứng bổ sung.

### Quy trình CI/CD

Workflow nằm trong [`.github/workflows/ci.yaml`](.github/workflows/ci.yaml).

| Sự kiện | Unit test | SonarQube Cloud | Docker build + Trivy | Đẩy lên ECR + triển khai ECS |
| --- | --- | --- | --- | --- |
| Push lên `feature/**` | Có | Bỏ qua | Có | Không |
| Pull request vào `master` | Có | Có | Có | Không |
| Push lên `master` | Có | Có | Có | Có, sau khi các bước kiểm tra đạt |

Job unit test chạy `npm ci` và Jest kèm coverage. Job image chỉ chạy khi job kiểm tra chất lượng thành công; bước đẩy image lên ECR và triển khai chỉ chạy khi push lên `master`.

Trivy làm job image thất bại nếu phát hiện lỗ hổng `HIGH` hoặc `CRITICAL` đã có bản sửa. Image phát hành được gắn tag theo Git commit SHA. Khi triển khai, GitHub Actions dùng OIDC để nhận quyền IAM trên AWS, tạo phiên bản ECS task definition mới, cập nhật ECS service và chờ service ổn định. GitHub không lưu AWS access key dài hạn.

ECS dùng **chiến lược canary có sẵn**: chuyển 10% lưu lượng sang phiên bản mới trong 5 phút, sau đó chuyển 100% và tiếp tục theo dõi thêm 5 phút. Hệ thống không dùng Argo CD hay AWS CodeDeploy.

Cấu hình các **variables** sau trong GitHub Actions: `AWS_ROLE_ARN`, `AWS_REGION`, `ECR_REPOSITORY`, `ECS_CLUSTER`, `ECS_SERVICE`, `ECS_TASK_FAMILY`, `ECS_CONTAINER_NAME`. Lưu `SONAR_TOKEN` dưới dạng **secret**. Không commit thông tin đăng nhập hoặc token.

### Kiến trúc AWS và Terraform

Toàn bộ hạ tầng AWS được định nghĩa và cấp phát bằng Terraform; không cần tạo tài nguyên thủ công qua AWS Console.

- [`terraform/bootstrap`](terraform/bootstrap/main.tf) tạo S3 bucket lưu Terraform state có versioning và mã hóa, cùng ECR repository có image tag bất biến.
- [`terraform/app`](terraform/app/main.tf) tạo VPC, hai public subnet ở hai Availability Zone, security group, ALB công khai, hai target group, ECS Fargate service, CloudWatch log group, IAM role, GitHub OIDC provider và ECS Service Auto Scaling.

ALB nhận HTTP qua cổng 80. Chỉ security group của ALB được truy cập container ứng dụng qua cổng 3000. ECS service khởi chạy với **2 task** và tự điều chỉnh trong khoảng **2–4 task**, theo mục tiêu **CPU trung bình 60%**. Các task gửi log ứng dụng tới `/ecs/goldenowl-app`; log được lưu 7 ngày.

#### Cấp phát môi trường mới

Yêu cầu: Terraform >= 1.10, Docker, AWS CLI và AWS credentials có quyền tạo các tài nguyên nêu trên. Cần Node.js 24 và npm nếu muốn chạy ứng dụng trên máy cá nhân.

Các lệnh sau dành cho **lần triển khai mới**. S3 backend, tên ECR, AWS region và điều kiện tin cậy GitHub OIDC trong Terraform đang gắn với tài khoản và fork này; hãy sửa trước khi dùng lại. Cần giữ Terraform state của bootstrap: chạy từ bản clone khác mà không có state có thể xung đột với tài nguyên đã tạo.

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
terraform -chdir=terraform/app apply
terraform -chdir=terraform/app output deployment_url
```

ECS task definition ban đầu dùng image `bootstrap` trên ECR. Các bản phát hành tiếp theo do GitHub Actions build và triển khai. Tài nguyên AWS có thể phát sinh chi phí trong thời gian hoạt động.

### Docker image

[Dockerfile](Dockerfile) dùng multi-stage build. Node.js 24 Alpine cài các production dependencies bằng `npm ci --omit=dev`; giai đoạn chạy ứng dụng dùng distroless Node.js 24 với user không có quyền root `65532`. [`.dockerignore`](.dockerignore) loại các file không cần thiết khỏi build context.

Image đã đẩy lên ECR có kích thước **56.040.949 byte (~56,0 MB)**. Docker Desktop báo **220 MB dung lượng đĩa** cho image cục bộ; đây là hai cách đo khác nhau.

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

**Giới hạn:** ALB hiện phục vụ HTTP, chưa có HTTPS. Chưa cấu hình tự động rollback.
