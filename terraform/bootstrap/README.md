# Bootstrap

Run once to create the Terraform state backend.

1. `cd terraform/bootstrap`
2. `terraform init`
3. `terraform apply`
4. Note the `state_bucket` and `lock_table` outputs
5. Update `../backend.tf` with these values
