# Generate a random 4-digit integer
resource "random_integer" "suffix" {
  min = 1000
  max = 9999
}

locals {
  unique_name = "${terraform.workspace}-${random_integer.suffix.result}"

  is_web = var.server_type == "Web"

  common_tags = {
    CostCenter        = var.cost_center,
    "Terraform Managed" = "true"
  }

  # NLB and target group names are capped at 32 characters.
  lb_name = substr("${local.unique_name}-nlb", 0, 32)
  tg_name = substr("${local.unique_name}-tg8080", 0, 32)
}


# ---------------------------------------------------------------------------
# Look up the existing shared network. This module never creates networks.
# ---------------------------------------------------------------------------

data "aws_vpc" "shared" {
  tags = {
    Name = var.vpc_name
  }
}

# All subnets whose Name tag matches the server type ("Web", "App", "Bastion").
data "aws_subnets" "tier" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.shared.id]
  }

  filter {
    name   = "tag:Name"
    values = [var.server_type]
  }
}

data "aws_ssm_parameter" "windows_ami" {
  name = var.windows_ami_ssm_parameter
}

# ---------------------------------------------------------------------------
# Instance security group: RDP for every server type, plus 8080 from the NLB
# for Web servers.
# ---------------------------------------------------------------------------

resource "aws_security_group" "instance" {
  name_prefix = "${local.unique_name}-"
  description = "${var.server_type} server ${local.unique_name}"
  vpc_id      = data.aws_vpc.shared.id

  tags = {
    Name = "${local.unique_name}-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "rdp" {
  for_each = toset(var.rdp_allowed_cidrs)

  security_group_id = aws_security_group.instance.id
  description       = "RDP"
  ip_protocol       = "tcp"
  from_port         = 3389
  to_port           = 3389
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_ingress_rule" "web_from_nlb" {
  count = local.is_web ? 1 : 0

  security_group_id            = aws_security_group.instance.id
  description                  = "HTTP 8080 from NLB"
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
  referenced_security_group_id = aws_security_group.nlb[0].id
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.instance.id
  description       = "Outbound internet"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ---------------------------------------------------------------------------
# Windows instance
# ---------------------------------------------------------------------------

resource "aws_instance" "this" {
  ami                         = data.aws_ssm_parameter.windows_ami.value
  instance_type               = var.instance_types[var.instance_size]
  subnet_id                   = try(data.aws_subnets.tier.ids[0], null)
  vpc_security_group_ids      = [aws_security_group.instance.id]
  associate_public_ip_address = true
  key_name                    = var.key_name

  user_data                   = local.is_web ? file("${path.module}/templates/web_user_data.ps1") : null
  user_data_replace_on_change = true

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_size
    encrypted   = true

    # default_tags does not reach volumes created through the instance.
    tags = merge(local.common_tags, { Name = "${local.unique_name}-root" })
  }

  tags = {
    Name       = local.unique_name
    ServerType = var.server_type
  }

  lifecycle {
    # The AMI parameter always points at the newest image; don't rebuild
    # running servers every time AWS publishes a new one.
    ignore_changes = [ami]

    precondition {
      condition     = length(data.aws_subnets.tier.ids) > 0
      error_message = "No subnet named '${var.server_type}' exists in VPC '${var.vpc_name}'. Apply the network-foundation stack first."
    }
  }
}

# ---------------------------------------------------------------------------
# Web only: Network Load Balancer on port 8080
# ---------------------------------------------------------------------------

resource "aws_security_group" "nlb" {
  count = local.is_web ? 1 : 0

  name_prefix = "${local.unique_name}-nlb-"
  description = "NLB for ${local.unique_name}"
  vpc_id      = data.aws_vpc.shared.id

  tags = {
    Name = "${local.unique_name}-nlb-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "nlb_8080" {
  for_each = local.is_web ? toset(var.web_allowed_cidrs) : toset([])

  security_group_id = aws_security_group.nlb[0].id
  description       = "HTTP 8080"
  ip_protocol       = "tcp"
  from_port         = 8080
  to_port           = 8080
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_egress_rule" "nlb_to_targets" {
  count = local.is_web ? 1 : 0

  security_group_id            = aws_security_group.nlb[0].id
  description                  = "To web targets on 8080"
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
  referenced_security_group_id = aws_security_group.instance.id
}

resource "aws_lb" "web" {
  count = local.is_web ? 1 : 0

  name               = local.lb_name
  load_balancer_type = "network"
  internal           = false
  subnets            = data.aws_subnets.tier.ids
  security_groups    = [aws_security_group.nlb[0].id]

  # The instance lives in one Web subnet; let NLB nodes in other AZs reach it.
  enable_cross_zone_load_balancing = true
}

resource "aws_lb_target_group" "web" {
  count = local.is_web ? 1 : 0

  name        = local.tg_name
  port        = 8080
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = data.aws_vpc.shared.id

  health_check {
    protocol = "HTTP"
    port     = "8080"
    path     = "/"
  }
}

resource "aws_lb_target_group_attachment" "web" {
  count = local.is_web ? 1 : 0

  target_group_arn = aws_lb_target_group.web[0].arn
  target_id        = aws_instance.this.id
  port             = 8080
}

resource "aws_lb_listener" "web" {
  count = local.is_web ? 1 : 0

  load_balancer_arn = aws_lb.web[0].arn
  port              = 8080
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web[0].arn
  }
}
