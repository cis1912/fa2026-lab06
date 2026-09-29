# Lab 05: Terraform

So far you've configured infrastructure by hand: `docker run` flags in Lab 01, a `docker-compose.yml` in Lab 02, `kubectl` commands in the Kubernetes lab. Each time, the pattern was the same — you describe what you want by typing commands (or filling in a manifest) and watching what happens. That works fine for two or three resources.

Real cloud infrastructure rarely stays at two or three resources, and cloud resources have **dependencies**: a subnet needs a VPC to exist first, a security group needs to attach to a VPC, and so on. Creating them by hand means you juggle IDs between commands and delete things in exactly the right order, or the cloud provider (rightfully) refuses. **Terraform** lets you _describe_ the infrastructure you want in a file, and it figures out the dependency graph, the creation order, and the teardown order for you.

This lab points Terraform (and the AWS CLI) at a **real AWS account**. Everything you create — a VPC, a subnet, a security group — is a real resource in that account, tracked with a real dependency graph. None of the resource types this lab uses (VPC, subnet, security group) carry any charge on their own, but you're still working against a live account: follow the cleanup steps at the end of each part, and never commit your AWS credentials to git.

## Setup

You'll need:

- **[Terraform CLI](https://developer.hashicorp.com/terraform/install)** — `brew install terraform` on macOS, or see the link for other platforms.
- **[AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)** — `brew install awscli` on macOS.
- An AWS account and a set of AWS credentials — see below.

### AWS credentials

If your instructor gave you AWS credentials for this course (for example, an AWS Academy or sandbox account), use those and skip to **Configure the CLI** below.

Otherwise, set up your own account:

1. Create an [AWS account](https://aws.amazon.com/free/) if you don't already have one.
2. **Don't use your root account credentials for this lab.** In the AWS Console, go to **IAM → Users → Create user**, give it a name (e.g. `lab05-terraform`), and choose **Attach policies directly**. Attach `AmazonVPCFullAccess` — it covers everything this lab creates (VPCs, subnets, security groups).
3. Open the new user, go to the **Security credentials** tab, and **Create access key**. Choose the **Command Line Interface (CLI)** use case. Save the Access Key ID and Secret Access Key shown — the secret is only ever shown once.

#### Configure the CLI

```bash
aws configure
```

Enter your Access Key ID, Secret Access Key, a default region (use `us-east-1` to match `main.tf`), and `json` for the output format. This writes to `~/.aws/credentials` and `~/.aws/config` — both Terraform and the AWS CLI read from there automatically, so you won't need to export anything by hand.

Verify it worked:

```bash
aws sts get-caller-identity
```

You should see your account ID and the IAM user's ARN. If this errors, re-run `aws configure` and double-check the keys.

Every `aws` command below runs against this real account and region — no `--endpoint-url` flag, no dummy credentials.

## Part A: The Manual Way

You're going to stand up a small, real network shape by hand: a VPC, a subnet inside it, and a security group attached to it that allows SSH. Run each command and note the ID in its output — you'll need it for the next command.

```bash
aws ec2 create-vpc --cidr-block 10.0.0.0/16
```

Copy the `VpcId` from the output, then create a subnet inside that VPC:

```bash
aws ec2 create-subnet --vpc-id <VPC_ID> --cidr-block 10.0.1.0/24
```

Copy the `SubnetId`, then create a security group in the same VPC:

```bash
aws ec2 create-security-group --group-name lab05-sg --description "lab 05" --vpc-id <VPC_ID>
```

Copy the `GroupId`, then open port 22 on it:

```bash
aws ec2 authorize-security-group-ingress --group-id <GROUP_ID> --protocol tcp --port 22 --cidr 0.0.0.0/0
```

Confirm it all exists (either in the output below, or in the [AWS Console VPC dashboard](https://console.aws.amazon.com/vpcconsole/)):

```bash
aws ec2 describe-vpcs
```

Now tear it down. Try deleting the VPC first:

```bash
aws ec2 delete-vpc --vpc-id <VPC_ID>
```

**This fails.** The VPC still has a subnet and a security group attached — AWS won't delete something that other resources depend on. You have to delete in the reverse of the order you created them:

```bash
aws ec2 delete-security-group --group-id <GROUP_ID>
aws ec2 delete-subnet --subnet-id <SUBNET_ID>
aws ec2 delete-vpc --vpc-id <VPC_ID>
```

Three resources, and you already had to track three IDs by hand and remember the correct order both ways. Imagine this with twenty resources, or coming back to clean it up after six months with no notes.

## Part B: The Terraform Way

The `terraform/` directory has a starter `main.tf` with the AWS provider configured for your real account (it reads the credentials you set up with `aws configure`). It defines the same three resources — a VPC, a subnet, and a security group — but a few pieces are marked `<FILL_IN>`. Fill them in:

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
- If `terraform apply` errors with something like `NoCredentialProviders` or `UnauthorizedOperation`, re-run `aws sts get-caller-identity` to confirm your credentials are configured and the IAM user has `AmazonVPCFullAccess`.
- **Always run `terraform destroy` when you're done**, and double check the [AWS Console VPC dashboard](https://console.aws.amazon.com/vpcconsole/) afterward — an account can only have a limited number of VPCs per region, so leftover ones from a previous run of this lab can block you from creating new ones.
- Never commit `~/.aws/credentials`, `terraform.tfstate` (it can contain resource details), or any file with a hardcoded access key. `terraform.tfstate` is already covered by `.gitignore` in this repo.
