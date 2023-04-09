
resource "aws_s3_bucket" "ssm_bucket" {
  bucket = var.bucket_name
}

resource "aws_s3_bucket_versioning" "ssm_bucket" {
  bucket = aws_s3_bucket.ssm_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_acl" "ssm_bucket" {
  bucket = aws_s3_bucket.ssm_bucket.id
  acl    = "private"
}

resource "aws_s3_bucket_public_access_block" "ssm_bucket" {
  bucket = aws_s3_bucket.ssm_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ssm_bucket" {
  bucket = aws_s3_bucket.ssm_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "ssm_bucket" {
  bucket     = aws_s3_bucket.ssm_bucket.id
  depends_on = [aws_s3_bucket_versioning.ssm_bucket]


  rule {
    id = "ssm"

    filter {
      prefix = "/"
    }

    # expiration {
    #   days = 90
    # }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    status = "Enabled"
  }
}


resource "aws_s3_bucket_policy" "ssm_bucket" {
  bucket = aws_s3_bucket.ssm_bucket.id
  policy = data.aws_iam_policy_document.ssm_bucket.json
}

data "aws_iam_policy_document" "ssm_bucket" {

  statement {
    sid    = "EncryptionConfig"
    effect = "Allow"

    principals {
      type = "AWS"
      identifiers = [
        var.stage_role,
        var.prod_role,
      ]
    }
    actions = [
      "s3:GetEncryptionConfiguration",
    ]
    resources = [
      aws_s3_bucket.ssm_bucket.arn,
    ]
  }
  statement {
    sid    = "SSMPutLogs_Stage"
    effect = "Allow"

    principals {
      type = "AWS"
      identifiers = [
        var.stage_role,
      ]
    }

    actions = [
      "s3:PutObject",
      "s3:PutObjectAcl",
    ]
    resources = [
      "${aws_s3_bucket.ssm_bucket.arn}${var.stage_prefix}",
      "${aws_s3_bucket.ssm_bucket.arn}${var.stage_prefix}/*",
    ]
  }

  statement {
    sid    = "SSMPutLogs_Prod"
    effect = "Allow"

    principals {
      type = "AWS"
      identifiers = [
        var.prod_role,
      ]
    }

    actions = [
      "s3:PutObject",
      "s3:PutObjectAcl",
    ]
    resources = [
      "${aws_s3_bucket.ssm_bucket.arn}${var.prod_prefix}",
      "${aws_s3_bucket.ssm_bucket.arn}${var.prod_prefix}/*",
    ]
  }
}
