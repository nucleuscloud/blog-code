

resource "aws_ssm_document" "session_manager_prefs" {
  name            = "SSM-SessionManagerRunShell"
  document_type   = "Session"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "1.0"
    description   = "Document to hold regional settings for Session Manager"
    sessionType   = "Standard_Stream"
    inputs = {
      kmsKeyId                    = aws_kms_key.ssm_key.id
      s3BucketName                = var.logs_bucket_name
      s3KeyPrefix                 = "ssm/${var.account_id}"
      s3EncryptionEnabled         = true
      cloudWatchLogGroupName      = ""
      cloudWatchEncryptionEnabled = true
      cloudWatchStreamingEnabled  = false
      idleSessionTimeout          = 60
      maxSessionDuration          = null
      runAsEnabled                = false
      shellProfile = {
        linux   = ""
        windows = ""
      }
    }
  })
}

resource "aws_kms_key" "ssm_key" {
  description             = "Encrypts SSM User Sessions"
  deletion_window_in_days = 10
  enable_key_rotation     = true
}
