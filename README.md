# Lab 05: Terraform

So far you've configured infrastructure by hand: `docker run` flags in Lab 01, a `docker-compose.yml` in Lab 02, `kubectl` commands in the Kubernetes lab. Each time, the pattern was the same — you describe what you want by typing commands (or filling in a manifest) and watching what happens. That works fine for two or three resources.

Real cloud infrastructure rarely stays at two or three resources, and cloud resources have **dependencies**: a subnet needs a VPC to exist first, a security group needs to attach to a VPC, and so on. Creating them by hand means you juggle IDs between commands and delete things in exactly the right order, or the cloud provider (rightfully) refuses. **Terraform** lets you _describe_ the infrastructure you want in a file, and it figures out the dependency graph, the creation order, and the teardown order for you.

To keep this lab free and account-free, we'll point Terraform at **[LocalStack](https://www.localstack.cloud/)**, a Docker container that emulates real AWS APIs on your machine. Everything you do here uses the same AWS provider and the same HCL syntax you'd use against a real AWS account — only the endpoint changes.

# Instructions

First, fork this repository on GitHub and then clone your fork to your local machine.

```bash
git clone git@github.com:<your-username>/lab-05-terraform.git
```

Work in the cloned repository to complete the lab exercises, then submit this repo to Gradescope.

## Setup

You'll need:

- **Docker** (already installed from Lab 01) — runs LocalStack.
- **[Terraform CLI](https://developer.hashicorp.com/terraform/install)** — `brew install terraform` on macOS, or see the link for other platforms.
- **[AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)** — `brew install awscli` on macOS.

Start LocalStack:

```bash
docker compose up -d
```

It's ready once this returns healthy:

```bash
curl http://localhost:4566/_localstack/health
```

LocalStack doesn't check credentials, but the AWS CLI still requires _something_ be set. Export a dummy profile once per terminal session:

```bash
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1
```

Every `aws` command below is pointed at LocalStack with `--endpoint-url=http://localhost:4566` — nothing here ever touches a real AWS account.

`docker compose up -d` also starts [StackPort](https://github.com/DaviReisVieira/stackport), a third-party, open-source GUI for browsing what's in LocalStack. It's entirely optional (everything in this lab works from the CLI) but if you'd rather _see_ your VPC, subnet, and security group instead of reading JSON, open **http://localhost:8080** at any point in either part below.

## Part A: The Manual Way

You're going to stand up a small, real network shape by hand: a VPC, a subnet inside it, and a security group attached to it that allows SSH. Run each command and note the ID in its output — you'll need it for the next command.

```bash
aws ec2 create-vpc --cidr-block 10.0.0.0/16 --endpoint-url=http://localhost:4566
```

Copy the `VpcId` from the output, then create a subnet inside that VPC:

```bash
aws ec2 create-subnet --vpc-id <VPC_ID> --cidr-block 10.0.1.0/24 --endpoint-url=http://localhost:4566
```

Copy the `SubnetId`, then create a security group in the same VPC:

```bash
aws ec2 create-security-group --group-name lab05-sg --description "lab 05" --vpc-id <VPC_ID> --endpoint-url=http://localhost:4566
```

Copy the `GroupId`, then open port 22 on it:

```bash
aws ec2 authorize-security-group-ingress --group-id <GROUP_ID> --protocol tcp --port 22 --cidr 0.0.0.0/0 --endpoint-url=http://localhost:4566
```

Confirm it all exists:

```bash
aws ec2 describe-vpcs --endpoint-url=http://localhost:4566
```

Now tear it down. Try deleting the VPC first:

```bash
aws ec2 delete-vpc --vpc-id <VPC_ID> --endpoint-url=http://localhost:4566
```

**This fails.** The VPC still has a subnet and a security group attached — AWS won't delete something that other resources depend on. You have to delete in the reverse of the order you created them:

```bash
aws ec2 delete-security-group --group-id <GROUP_ID> --endpoint-url=http://localhost:4566
aws ec2 delete-subnet --subnet-id <SUBNET_ID> --endpoint-url=http://localhost:4566
aws ec2 delete-vpc --vpc-id <VPC_ID> --endpoint-url=http://localhost:4566
```

Three resources, and you already had to track three IDs by hand and remember the correct order both ways. Imagine this with twenty resources, or coming back to clean it up after six months with no notes.

## Part B: The Terraform Way

The `terraform/` directory has a starter `main.tf` with the AWS provider already pointed at LocalStack. It defines the same three resources — a VPC, a subnet, and a security group — but a few pieces are marked `<FILL_IN>`. Fill them in:

- The VPC's `cidr_block`.
- The subnet's `vpc_id` — don't hardcode an ID, **reference the VPC resource block above it** (`aws_vpc.main.id`). This is the whole point: Terraform resolves that reference into the real ID and creates things in the right order automatically.
- The security group's `vpc_id` — same idea.

Once filled in:

```bash
cd terraform
terraform init
terraform plan
```

`plan` shows you exactly what Terraform is about to create, before it touches anything. Review it, then:

```bash
terraform apply
```

Type `yes` to confirm. Terraform creates the VPC, subnet, and security group — in the correct order — and prints the IDs as outputs. Compare this to Part A: you never typed an ID anywhere.

Look at `terraform.tfstate` — this is how Terraform knows what it created and how the pieces relate, so _it_ remembers the IDs, not you.

Now tear it down:

```bash
terraform destroy
```

One command. Terraform reads its own dependency graph and deletes the security group and subnet before the VPC, without you having to think about ordering at all.

## Reflection

You don't need to write this down, but you should be able to answer if asked: Part A and Part B created the exact same three AWS resources. What did Terraform actually do for you that the raw `aws` commands didn't? And what would go wrong in Part A's approach if two people on a team were both manually managing the same infrastructure?

## Tips

- `terraform fmt` reformats your `.tf` files consistently.
- `terraform state list` shows every resource Terraform is currently tracking.
- If `terraform apply` errors about the LocalStack endpoint, double check `docker compose ps` shows `localstack` as running.
- `docker compose down` stops LocalStack; add `-v` to also wipe its data volume.
