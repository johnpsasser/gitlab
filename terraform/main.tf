provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      ManagedBy   = "terraform"
      Environment = "production"
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

# --- Networking ---
module "networking" {
  source       = "./modules/networking"
  project_name = var.project_name
  vpc_cidr     = var.vpc_cidr
  aws_region   = var.aws_region
}

# --- Monitoring ---
module "monitoring" {
  source             = "./modules/monitoring"
  project_name       = var.project_name
  gitlab_instance_id = module.gitlab.instance_id
}

# --- GitLab ---
module "gitlab" {
  source            = "./modules/gitlab"
  project_name      = var.project_name
  vpc_id            = module.networking.vpc_id
  subnet_id         = module.networking.private_subnet_ids[0]
  security_group_id = module.networking.gitlab_security_group_id
  instance_type     = var.instance_type
  data_volume_size  = var.data_volume_size
  domain_name       = var.domain_name
  google_oauth_hd   = var.google_oauth_hd
}

# --- ALB ---
module "alb" {
  source             = "./modules/alb"
  project_name       = var.project_name
  vpc_id             = module.networking.vpc_id
  subnet_ids         = module.networking.public_subnet_ids
  security_group_id  = module.networking.alb_security_group_id
  domain_name        = var.domain_name
  gitlab_instance_id = module.gitlab.instance_id
}

# --- WAF ---
module "waf" {
  source       = "./modules/waf"
  project_name = var.project_name
  alb_arn      = module.alb.alb_arn
}
