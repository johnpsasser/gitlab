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
  alias  = "dns_account"
  region = var.aws_region

  assume_role {
    role_arn = var.dns_account_role_arn
  }

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
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
  subnet_ids         = module.networking.private_subnet_ids
  security_group_id  = module.networking.alb_security_group_id
  domain_name        = var.domain_name
  route53_zone_id    = var.route53_zone_id
  gitlab_instance_id = module.gitlab.instance_id

  providers = {
    aws             = aws
    aws.dns_account = aws.dns_account
  }
}

# --- DNS ---
module "dns" {
  source       = "./modules/dns"
  project_name = var.project_name
  domain_name  = var.domain_name
  vpc_id       = module.networking.vpc_id
  alb_dns_name = module.alb.alb_dns_name
  alb_zone_id  = module.alb.alb_zone_id
}
