# SSM Patch Manager (SI-2: Flaw Remediation)

resource "aws_ssm_patch_baseline" "al2023" {
  name             = "${var.project_name}-al2023-patch-baseline"
  operating_system = "AMAZON_LINUX_2023"

  approval_rule {
    approve_after_days = 7
    compliance_level   = "CRITICAL"

    patch_filter {
      key    = "CLASSIFICATION"
      values = ["Security"]
    }

    patch_filter {
      key    = "SEVERITY"
      values = ["Critical", "Important"]
    }
  }

  approval_rule {
    approve_after_days = 14
    compliance_level   = "HIGH"

    patch_filter {
      key    = "CLASSIFICATION"
      values = ["Security", "Bugfix"]
    }
  }

  tags = {
    Name = "${var.project_name}-patch-baseline"
  }
}

resource "aws_ssm_patch_group" "gitlab" {
  baseline_id = aws_ssm_patch_baseline.al2023.id
  patch_group = var.project_name
}

resource "aws_ssm_maintenance_window" "patching" {
  name                       = "${var.project_name}-patch-window"
  schedule                   = "cron(0 4 ? * SUN *)"
  duration                   = 3
  cutoff                     = 1
  allow_unassociated_targets = false

  tags = {
    Name = "${var.project_name}-patch-window"
  }
}

resource "aws_ssm_maintenance_window_target" "gitlab" {
  window_id     = aws_ssm_maintenance_window.patching.id
  resource_type = "INSTANCE"
  name          = "${var.project_name}-ec2-target"

  targets {
    key    = "InstanceIds"
    values = [aws_instance.gitlab.id]
  }
}

resource "aws_ssm_maintenance_window_task" "patch_scan_and_install" {
  window_id       = aws_ssm_maintenance_window.patching.id
  task_type       = "RUN_COMMAND"
  task_arn        = "AWS-RunPatchBaseline"
  priority        = 1
  max_concurrency = "1"
  max_errors      = "0"

  targets {
    key    = "WindowTargetIds"
    values = [aws_ssm_maintenance_window_target.gitlab.id]
  }

  task_invocation_parameters {
    run_command_parameters {
      parameter {
        name   = "Operation"
        values = ["Install"]
      }
      parameter {
        name   = "RebootOption"
        values = ["RebootIfNeeded"]
      }
    }
  }
}
