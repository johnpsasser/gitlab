provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project            = var.project_name
      ManagedBy          = "terraform"
      Environment        = "production"
      DataClassification = var.data_classification
    }
  }
}

provider "aws" {
  alias  = "replication"
  region = var.backup_replication_region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
    }
  }
}

# --- KMS ---
module "kms" {
  source       = "./modules/kms"
  project_name = var.project_name
  aws_region   = var.aws_region
}

# --- Networking ---
module "networking" {
  source       = "./modules/networking"
  project_name = var.project_name
  vpc_cidr     = var.vpc_cidr
  aws_region   = var.aws_region
  kms_key_arn  = module.kms.general_key_arn
}

# --- Monitoring ---
module "monitoring" {
  source                 = "./modules/monitoring"
  project_name           = var.project_name
  gitlab_instance_id     = module.gitlab.instance_id
  kms_key_arn            = module.kms.general_key_arn
  cloudtrail_kms_key_arn = module.kms.cloudtrail_key_arn
  alert_email            = var.alert_email
}

# --- GitLab ---
module "gitlab" {
  source = "./modules/gitlab"

  providers = {
    aws             = aws
    aws.replication = aws.replication
  }

  project_name              = var.project_name
  vpc_id                    = module.networking.vpc_id
  subnet_id                 = module.networking.private_subnet_ids[0]
  security_group_id         = module.networking.gitlab_security_group_id
  instance_type             = var.instance_type
  data_volume_size          = var.data_volume_size
  domain_name               = var.domain_name
  ebs_kms_key_id            = module.kms.ebs_key_id
  kms_key_id                = module.kms.general_key_id
  s3_access_logs_bucket_id  = module.networking.s3_access_logs_bucket_id
  use_fips_ami              = var.use_fips_ami
  enable_backup_replication = var.enable_backup_replication
  backup_replication_region = var.backup_replication_region
}

# --- ALB ---
module "alb" {
  source                   = "./modules/alb"
  project_name             = var.project_name
  vpc_id                   = module.networking.vpc_id
  subnet_ids               = module.networking.public_subnet_ids
  security_group_id        = module.networking.alb_security_group_id
  domain_name              = var.domain_name
  gitlab_instance_id       = module.gitlab.instance_id
  s3_access_logs_bucket_id = module.networking.s3_access_logs_bucket_id
}

# --- WAF ---
module "waf" {
  source       = "./modules/waf"
  project_name = var.project_name
  alb_arn      = module.alb.alb_arn
  kms_key_arn  = module.kms.general_key_arn
}

# --- Security (IL2 Continuous Monitoring) ---
module "security" {
  source       = "./modules/security"
  project_name = var.project_name
  aws_region   = var.aws_region
  kms_key_arn  = module.kms.general_key_arn
}

# --- Inactive Account Deactivation (AC-2(3)) ---
module "user_deactivation" {
  source             = "./modules/lambda-user-deactivation"
  project_name       = var.project_name
  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids
  domain_name        = var.domain_name
  kms_key_arn        = module.kms.general_key_arn
  kms_key_id         = module.kms.general_key_id
  sns_topic_arn      = module.monitoring.sns_topic_arn
}

# --- Secrets Rotation (IA-5(1)) ---
module "rotation" {
  source                   = "./modules/rotation"
  project_name             = var.project_name
  vpc_id                   = module.networking.vpc_id
  private_subnet_ids       = module.networking.private_subnet_ids
  gitlab_instance_id       = module.gitlab.instance_id
  root_password_secret_arn = module.gitlab.root_password_secret_arn
  kms_key_arn              = module.kms.general_key_arn
  sns_topic_arn            = module.monitoring.sns_topic_arn
}

# --- CISA Advisory Alerts (SI-5) ---
module "cisa_alerts" {
  source             = "./modules/lambda-cisa-alerts"
  project_name       = var.project_name
  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids
  kms_key_arn        = module.kms.general_key_arn
  sns_topic_arn      = module.monitoring.sns_topic_arn
}
