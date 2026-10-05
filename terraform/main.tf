terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# No access_key/secret_key here — the AWS provider picks up credentials
# from the "cis1912" profile you set up with `aws configure --profile
# cis1912` in the README's "AWS credentials" section.
provider "aws" {
  region  = "us-east-1"
  profile = "cis1912"
}

# Bucket names are global across all of AWS, not just your account — pick
# something unlikely to collide with anyone else's bucket.
resource "aws_s3_bucket" "main" {
  bucket = <FILL_IN> # e.g. "lab05-<your-pennkey>-website"
}

# Turns the bucket into a (very basic) web server: this is what tells S3 to
# treat GET requests for "/" as a request for index.html.
resource "aws_s3_bucket_website_configuration" "main" {
  # Reference the bucket resource above instead of hardcoding its name —
  # Terraform uses this to know it must create the bucket first.
  bucket = <FILL_IN>

  index_document {
    suffix = "index.html"
  }
}

# New buckets block all public access by default. Hosting a public website
# means explicitly turning that safety default off for this bucket.
resource "aws_s3_bucket_public_access_block" "main" {
  bucket = <FILL_IN> # reference the bucket, same as above

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# Turning off the block above doesn't grant access by itself — this policy
# is what actually says "anyone can read objects in this bucket."
resource "aws_s3_bucket_policy" "main" {
  bucket = <FILL_IN> # reference the bucket, same as above

  # There's no Terraform attribute linking this resource to the public
  # access block above (the policy JSON below is just a string), so
  # Terraform can't infer the dependency on its own. depends_on says it
  # explicitly: apply the public access block before this policy, or AWS
  # will reject a public policy on a bucket that's still blocking one.
  depends_on = [aws_s3_bucket_public_access_block.main]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.main.arn}/*"
      }
    ]
  })
}

# The actual page that gets served. Terraform manages this object just like
# any other resource — it'll show up in `terraform state list` and get
# deleted on `terraform destroy`, same as the bucket.
resource "aws_s3_object" "index" {
  bucket       = <FILL_IN> # reference the bucket, same as above
  key          = "index.html"
  content_type = "text/html"
  content      = <<-HTML
    <!DOCTYPE html>
    <html>
      <head><title>Lab 05</title></head>
      <body><h1>Hello from Terraform!</h1></body>
    </html>
  HTML
}

output "website_url" {
  value = "http://${aws_s3_bucket_website_configuration.main.website_endpoint}"
}
