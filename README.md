# Lab 05: Terraform

So far you've configured infrastructure by hand: `docker run` flags in Lab 01, a `docker-compose.yml` in Lab 02, `kubectl` commands in the Kubernetes lab. Each time, the pattern was the same — you describe what you want by typing commands (or filling in a manifest) and watching what happens. That works fine for a resource or two.

Real infrastructure rarely stays that simple, and cloud resources have **dependencies**: a bucket policy needs the bucket to exist first, and granting public access means overriding an account-level safety default before the policy will even be accepted. Creating these by hand means remembering the right order and deleting things in reverse, or the cloud provider (rightfully) refuses. **Terraform** lets you _describe_ the infrastructure you want in a file, and it figures out the dependency graph, the creation order, and the teardown order for you.

In this lab you'll deploy a real, publicly reachable website — a static HTML page served directly out of an S3 bucket, no server to manage — first by hand, then with Terraform. This lab points Terraform (and the AWS CLI) at a **real AWS account**. The resources it creates (an S3 bucket, a bucket policy, one small object) are effectively free at this scale, but you're still working against a live account: follow the cleanup steps at the end of each part, and never commit your AWS credentials to git.

## Setup

You'll need:

- **[Terraform CLI](https://developer.hashicorp.com/terraform/install)** — `brew install terraform` on macOS, or see the link for other platforms.
- **[AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)** — `brew install awscli` on macOS.
- An AWS account and a set of AWS credentials — see below.

### AWS credentials

You should have received AWS credentials for this course! Check your inbox, and let us know if you need help.

This lab can be done with both the AWS CLI or the AWS Management Console. You're free to use whichever you prefer, but the instructions below guide you to use the AWS CLI.

#### Configure the CLI

Set these credentials up under a named profile called `cis1912` — `main.tf` is already configured to use that exact profile name, so it has to match:

```bash
aws configure --profile cis1912
```

Enter your Access Key ID, Secret Access Key, a default region (use `us-east-1` to match `main.tf`), and `json` for the output format. This writes to `~/.aws/credentials` and `~/.aws/config` under a `[cis1912]` profile — both Terraform and the AWS CLI read from there automatically once you point them at it.

To avoid typing `--profile cis1912` on every command below, export it once per terminal session:

```bash
export AWS_PROFILE=cis1912
```

Verify it worked:

```bash
aws sts get-caller-identity
```

You should see your account ID and the IAM user's ARN. If this errors, re-run `aws configure --profile cis1912` and double-check the keys.

Every `aws` command below runs against this real account and region — no `--endpoint-url` flag, no dummy credentials.

## Part A: The Manual Way

You're going to stand up a public website by hand, piece by piece, and watch what happens when you skip a step. Pick a bucket name first — S3 bucket names are **global across all of AWS**, not just your account, so something like `lab05-<your-pennkey>-website` is a safe bet. Export it so you don't retype it:

```bash
export BUCKET_NAME=lab05-<your-pennkey>-website
```

Create the bucket:

```bash
aws s3api create-bucket --bucket $BUCKET_NAME --region us-east-1
```

Turn it into a website — this tells S3 to serve `index.html` for requests to `/`:

```bash
aws s3 website s3://$BUCKET_NAME/ --index-document index.html
```

Upload a page:

```bash
echo '<h1>Hello from the manual way!</h1>' > index.html
aws s3 cp index.html s3://$BUCKET_NAME/index.html --content-type text/html
```

Now try to load it:

```bash
curl "http://$BUCKET_NAME.s3-website-us-east-1.amazonaws.com/"
```

**This fails with `AccessDenied`.** New buckets block all public access by default, and even if they didn't, nothing has granted anyone permission to read your object. Fix both, in order:

```bash
aws s3api put-public-access-block --bucket $BUCKET_NAME --public-access-block-configuration \
  BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false
```

```bash
cat > policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "PublicReadGetObject",
    "Effect": "Allow",
    "Principal": "*",
    "Action": "s3:GetObject",
    "Resource": "arn:aws:s3:::$BUCKET_NAME/*"
  }]
}
EOF
aws s3api put-bucket-policy --bucket $BUCKET_NAME --policy file://policy.json
```

Load it again — it should work this time:

```bash
curl "http://$BUCKET_NAME.s3-website-us-east-1.amazonaws.com/"
```

You can also open that same URL in a browser.

Now tear it down. Try deleting the bucket first:

```bash
aws s3api delete-bucket --bucket $BUCKET_NAME
```

**This fails.** The bucket still has an object in it — AWS won't delete a bucket that isn't empty. Empty it first, then delete it:

```bash
aws s3 rm s3://$BUCKET_NAME --recursive
aws s3api delete-bucket --bucket $BUCKET_NAME
```

Two resources (the bucket and the object inside it) plus a policy and a public-access setting, and you already had to get the order right in both directions — and remember to empty the bucket, a step with no error message pointing you to it until you hit it.

## Part B: The Terraform Way

The `terraform/` directory has a starter `main.tf` with the AWS provider configured for your real account (it reads the `cis1912` profile you set up with `aws configure --profile cis1912`). It defines the same website — a bucket, a website configuration, a public-access setting, a bucket policy, and the `index.html` object — but a few pieces are marked `<FILL_IN>`. Fill them in:

- The bucket's `bucket` name — pick something globally unique, e.g. `lab05-<your-pennkey>-website`.
- The website configuration's `bucket` — don't hardcode the name, **reference the bucket resource above it** (`aws_s3_bucket.main.id`). This is the whole point: Terraform resolves that reference into the real bucket and creates things in the right order automatically.
- The public access block's `bucket` — same idea.
- The bucket policy's `bucket` — same idea.
- The object's `bucket` — same idea.

Read the comment above `aws_s3_bucket_policy` about `depends_on` — it's already filled in for you, but make sure you understand why it's there before moving on.

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

Type `yes` to confirm. Terraform creates the bucket, configures it as a website, opens public access, attaches the policy, and uploads the object — in the correct order — and prints the live URL as an output. Compare this to Part A: you never typed a bucket name into more than one place.

Open the URL from the `website_url` output in your browser, or:

```bash
curl $(terraform output -raw website_url)
```

Look at `terraform.tfstate` — this is how Terraform knows what it created and how the pieces relate, so _it_ remembers the names and ARNs, not you.

When you're done, tear it down:

```bash
terraform destroy
```

Type `yes` to confirm. Notice that this works in one shot, with no separate "empty the bucket" step — Terraform tracks `aws_s3_object.index` as a resource it manages, so it deletes the object before the bucket as part of the same dependency graph.

## Reflection

You don't need to write this down, but you should be able to answer if asked:

- Part A and Part B created the exact same resources. What did Terraform actually do for you that the raw `aws` commands didn't? What would go wrong in Part A's approach if two people on a team were both manually managing the same bucket?
- In Part A, deleting the bucket required a separate step to empty it first. Why didn't `terraform destroy` need an equivalent step?
- There's no Terraform attribute connecting `aws_s3_bucket_policy` to `aws_s3_bucket_public_access_block` — so why does `main.tf` need an explicit `depends_on` between them?

## Tips

- `terraform fmt` reformats your `.tf` files consistently (run it only after filling in the `<FILL_IN>`s — it can't format a file with invalid syntax).
- `terraform state list` shows every resource Terraform is currently tracking.
- If `terraform apply` errors with `BucketAlreadyExists` (not `BucketAlreadyOwnedByYou`), someone else already owns that bucket name — pick a more unique one.
- If `terraform apply` errors with something like `NoCredentialProviders` or `UnauthorizedOperation`, re-run `aws sts get-caller-identity --profile cis1912` to confirm your credentials are configured under the right profile name. This lab needs `AmazonS3FullAccess`.
- If the website URL 403s after `apply`, double-check the public access block and bucket policy both reference the same bucket, and that `depends_on` is in place.
- **Always run `terraform destroy` when you're done**, and double check the [AWS Console S3 dashboard](https://console.aws.amazon.com/s3/) afterward for leftover buckets.
- Never commit `~/.aws/credentials`, `terraform.tfstate` (it can contain resource details), or any file with a hardcoded access key. `terraform.tfstate` is already covered by `.gitignore` in this repo.
