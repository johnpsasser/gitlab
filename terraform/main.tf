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

module "networking" {
  source       = "./modules/networking"
  project_name = var.project_name
  vpc_cidr     = var.vpc_cidr
  aws_region   = var.aws_region
}

module "monitoring" {
  source       = "./modules/monitoring"
  project_name = var.project_name
}
