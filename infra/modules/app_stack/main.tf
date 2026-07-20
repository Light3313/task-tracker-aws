# Default tags for all resources in this module
locals {
  name = "tt-${var.env_name}"

  tags = merge(var.tags, {
    Project     = "task-tracker"
    Environment = var.env_name
    ManagedBy   = "terraform"
  })

  # AMIs pinned (not floating SSM "latest") so instances aren't replaced on every new AL2023 —
  ami_al2023_arm    = "ami-02e447f4c654c7179" # AL2023 arm64  (NAT)
  ami_al2023_x86_64 = "ami-0fd6240f599091088" # AL2023 x86_64 (app)

  subnets = {
    public_1a  = { az = "us-east-1a", netnum = 1, tier = "public" }
    public_1b  = { az = "us-east-1b", netnum = 2, tier = "public" }
    private_1a = { az = "us-east-1a", netnum = 3, tier = "private" }
    private_1b = { az = "us-east-1b", netnum = 4, tier = "private" }
  }
}
