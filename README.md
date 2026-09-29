# Self-service Windows EC2 (Terraform no-code)

Two stacks with separate state:

| Stack | Who applies it | What it owns |
|---|---|---|
| `network-foundation/` | Platform team, **once per region** | VPC, Internet Gateway, route tables, subnets named `Web`, `App`, `Bastion` |
| `windows-vm/` | End users, via the no-code form, **once per server** | Windows instance, security group(s), and for `Web` an NLB on port 8080 |

## Why two stacks

The requirement is that networks are "not recreated if already present" and
that new VMs join existing networks. A single module that creates a network
only when a lookup comes back empty doesn't hold up in Terraform:

- On the next plan the lookup finds the network the module just created,
  the count flips to 0, and Terraform plans to destroy it.
- Destroying the first VM's workspace would remove the network every other
  VM is using.

So the network lives in its own long-lived state, and `windows-vm` only
**reads** it (`data "aws_vpc"` / `data "aws_subnets"` filtered on the `Name`
tag). Re-applying `network-foundation` is idempotent, so nothing gets
recreated. If the networks already exist outside Terraform, either skip
`network-foundation` and make sure the VPC/subnet `Name` tags match, or bring
them under management with `import` blocks.

## How the requirements map to the code

| Requirement | Where |
|---|---|
| Variable instance size | `instance_size` (micro/small/medium/large) → `instance_types` map |
| Server type Web/App/Bastion | `server_type` (validated) |
| CostCenter + `Terraform Managed = true` on all resources | provider `default_tags` in both stacks, plus `root_block_device.tags` for the EBS volume |
| Predefined networks Web/App/Bastion | `network-foundation` subnets tagged `Name = Web|App|Bastion` |
| IGW + outbound for all networks | one IGW, `0.0.0.0/0 → IGW` route on every network's route table |
| Server type → correct network | `data "aws_subnets"` filter `tag:Name = var.server_type` |
| Web → NLB :8080 + static page | `aws_lb`/listener/target group (count = Web only) + `templates/web_user_data.ps1` (IIS on 8080, `index.html` = "i am a web server") |
| RDP to all instances | `aws_vpc_security_group_ingress_rule.rdp` on 3389 from `rdp_allowed_cidrs` |
| VMs join existing networks | `windows-vm` has no network resources, only data sources |

## Rollout

1. **Network**: in its own workspace (or locally):
   ```bash
   cd network-foundation
   terraform init
   terraform apply -var="cost_center=CC-1234"
   ```
2. **Publish the no-code module** (HCP Terraform / Terraform Enterprise):
   - Put the contents of `windows-vm/` at the root of its own VCS repo named
     `terraform-aws-windows-vm`. The registry requires the `terraform-<provider>-<name>` name and the module at the repo root.
   - Registry → Publish → Module → pick the repo → tick **Add module to no-code provision allowlist**.
   - In the module's no-code settings, pin the dropdown options for
     `server_type` (Web, App, Bastion) and `instance_size`.
   - Create a variable set, attached to the project where no-code workspaces
     land, with AWS credentials (preferably dynamic provider credentials) and
     platform defaults such as `region`, `vpc_name`, and `rdp_allowed_cidrs`.
3. **Users** click *Provision workspace*, then fill in `server_type`,
   `instance_size`, `cost_center`, and optionally `key_name`.

   Note: VM named after workspace name.

Outputs: `public_ip` for RDP, and `web_url` (`http://<nlb-dns>:8080`) for Web servers.

## Things to tighten before production

- `rdp_allowed_cidrs` defaults to `0.0.0.0/0` to meet the "allow RDP" requirement
  literally. Set it to your corporate/VPN range in the variable set, or put
  App servers behind the Bastion and allow RDP to them only from the Bastion SG.
- All three networks are public subnets because the spec asks for IGW outbound
  on every network. For App servers, private subnets plus a NAT gateway are the
  usual pattern.
- Without `key_name` you can't decrypt the Administrator password. Use a key
  pair, or add an SSM instance profile and connect through Fleet Manager.
