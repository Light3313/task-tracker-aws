# CIS AWS Foundations Benchmark v5.0.0 - accepted findings

The account is checked against CIS v5.0.0 by AWS Config and Security Hub, both declared in
`infra/global/`. Most findings were fixed in code. These were not.

## Accepted

| Control | Not done | Reason |
|---|---|---|
| `IAM.6` | No hardware MFA on the root user | Root has a virtual MFA device and no access keys. A hardware key means buying and carrying a device. |
| `S3.20` | No MFA delete on the Terraform state bucket | Only the root user can enable it, and only through the CLI or API. That needs root access keys, which this account does not have by design. |
| `RDS.5` | Database runs in one Availability Zone | Multi-AZ doubles the instance cost. This project does not need a highly available database. |
| `S3.22` | Object-level write events not logged | Traffic to these buckets is Terraform state and AWS log delivery. Management events already record changes to the buckets themselves. |
| `S3.23` | Object-level read events not logged | Same traffic, same reason. Data events are charged per event. |

## Managed outside Terraform

**Account security contact.** The value is personal data. This
repository is public, so it is set in the console instead.

**Administrative identity.** The admin user and the group holding its policy are created by hand.
Terraform runs as that user. If Terraform owned the user, a failed apply could remove the access
needed to repair that apply. The state bucket is kept out of code for the same reason. The user also
has to outlive the application: destroying the stack must not remove access to the account.