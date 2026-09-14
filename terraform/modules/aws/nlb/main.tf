# Public AWS Network Load Balancer (NLB - Layer 4) fronting the Istio ingress gateway
# Delivers ultra-low latency TCP passthrough with direct target IP registration.
# Layer 7 WAF protection and DDoS mitigation are enforced at the Edge via CloudFront + AWS WAFv2.

resource "aws_security_group" "nlb" {
  name        = "${var.name}-${var.environment}-nlb-sg"
  description = "Public Network Load Balancer security group"
  vpc_id      = var.vpc_id

  ingress {
    description = "Allow HTTP entry"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTPS entry"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic to cluster nodes"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

resource "aws_lb" "this" {
  name                             = "${var.name}-${var.environment}-nlb"
  load_balancer_type               = "network"
  security_groups                  = [aws_security_group.nlb.id]
  subnets                          = var.public_subnet_ids
  enable_cross_zone_load_balancing = true

  tags = var.tags
}

# TCP Target Group pointing to the Istio ingress gateway Service in EKS
resource "aws_lb_target_group" "istio_gateway_http" {
  name        = "${var.name}-${var.environment}-istio-tg"
  port        = 80
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    protocol            = "TCP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 10
  }

  tags = var.tags
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.istio_gateway_http.arn
  }
}
