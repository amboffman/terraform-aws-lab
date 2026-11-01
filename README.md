# Terraform AWS Lab

A small full stack app on AWS, built and torn down entirely with Terraform.

**Phase 1 (this commit):** remote state in S3, a monthly budget alert, and a static frontend on a private S3 bucket served through CloudFront.

**Coming next:** VPC across 2 Availability Zones, RDS Postgres in private subnets, Lambda and API Gateway, CloudWatch alarm, GitHub Actions `terraform plan` on pull requests.

## Layout

```
bootstrap/   One-time setup: state bucket and budget alert. Local state. Never destroyed.
infra/       The actual app. Remote state in S3. Created and destroyed every session.
site/        Static files uploaded to the frontend bucket.
```

## Session 1 setup (about 2 hours)

### 1. Secure the AWS account

1. Sign in as root, turn on MFA for root, then stop using root.
2. Go to **IAM Identity Center** or **IAM > Users** and create a user for yourself (for example `anthony-admin`) with the `AdministratorAccess` policy and MFA on. This is fine for a personal lab. A production setup would use narrower roles.
3. Create an access key for that user (IAM > Users > your user > Security credentials > Create access key > Command Line Interface).

### 2. Install tools

macOS with Homebrew:

```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
brew install awscli
terraform -version   # needs 1.10 or newer
aws --version
```

Windows: `winget install Hashicorp.Terraform` and `winget install Amazon.AWSCLI`.

### 3. Configure a named AWS profile

```bash
aws configure --profile tf-lab
# Access key, secret key, region us-west-2, output json
aws sts get-caller-identity --profile tf-lab   # should print your IAM user, not root
```

### 4. Bootstrap (run once)

```bash
cd bootstrap
cp terraform.tfvars.example terraform.tfvars   # put your email in it
terraform init
terraform plan
terraform apply
```

Copy the `state_bucket` value it prints. AWS sends a confirmation email for the budget alert, so click it.

### 5. Point infra at the state bucket

```bash
cd ../infra
cp backend.hcl.example backend.hcl   # paste the bucket name
terraform init -backend-config=backend.hcl
```

## Every session after that

```bash
cd infra
terraform plan       # read this every time before applying
terraform apply
# open the site_url output (CloudFront takes about 5 minutes the first time)
terraform destroy    # at the end of every session
```

After changing files in `site/`, apply again, then clear the CloudFront cache:

```bash
aws cloudfront create-invalidation --profile tf-lab \
  --distribution-id $(terraform output -raw cloudfront_distribution_id) \
  --paths "/*"
```

## Cost notes

- Phase 1 is effectively free: S3 and CloudFront at this traffic level cost pennies.
- RDS (phase 2) is the expensive piece, so always `terraform destroy` at the end of a session.
- No NAT Gateway anywhere in this design. They run about $30+ a month.
- The budget alert emails you at 50% and 100% of $10.

## What each piece teaches for the SAA exam

| Piece | Exam topic |
| --- | --- |
| Private bucket + CloudFront OAC | S3 security, CloudFront origins, caching |
| Versioned, encrypted state bucket | S3 versioning, encryption at rest |
| Budget alert | Cost optimization domain |
| VPC, 2 AZs (phase 2) | Resilient architectures, subnets, security groups |
| RDS Multi-AZ toggle (phase 2) | Multi-AZ vs read replicas |
| Lambda + API Gateway (phase 2) | Serverless, decoupling |

## Things worth noticing while you build

- Run `terraform plan` and read it before every apply. Knowing what will change is the core skill interviewers ask about.
- Try `terraform state list` and `terraform show` after apply to see what Terraform tracks.
- Break something on purpose: delete the bucket policy in the console, then run `terraform plan` and watch it detect drift.
