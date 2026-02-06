############# Temporary migration variables #############

variable "migration_stage" {
  type        = string
  description = "Configuration for target group setup. Valid values are 'pre-migration', 'switch-traffic-to-temp', 'replace-service', 'switch-traffic-back-to-original'"
  nullable    = false
  validation {
    condition     = contains(["pre-migration", "switch-traffic-to-temp", "replace-service", "switch-traffic-back-to-original"], var.migration_stage)
    error_message = "Valid values for target group config:'pre-migration', 'switch-traffic-to-temp', 'replace-service', 'switch-traffic-back-to-original'"
  }
}

variable "temporary_migration_resources_active" {
  type        = bool
  default     = false
  description = "Whether to create temporary resources needed for data migration."
}

variable "HTTP2_compatible_reporting_image" {
  type        = string
  description = "Container image for the reporting service compatible with HTTP2."
  nullable    = false
}

variable "HTTP2_compatible_web_image" {
  type        = string
  description = "Container image for the web service compatible with HTTP2."
  nullable    = false
}

locals {
  migration_stage_configs = {
    "pre-migration" = {
      reporting_protocol             = "HTTP"
      reporting_protocol_version     = "HTTP1"
      web_protocol_version           = "HTTP1"
      web_temp_priority              = 49505
      web_temp_test_priority         = 21
      reporting_temp_priority        = 49005
      reporting_temp_test_priority   = 16
      reporting_service_health_check = "wget --no-cache --spider -S http://localhost:${local.container_ports.reporting}/reports/healthcheck || exit 1"
    }
    "switch-traffic-to-temp" = {
      reporting_protocol             = "HTTP"
      reporting_protocol_version     = "HTTP1"
      web_protocol_version           = "HTTP1"
      web_temp_priority              = 49400
      web_temp_test_priority         = 19
      reporting_temp_priority        = 48000
      reporting_temp_test_priority   = 14
      reporting_service_health_check = "wget --no-cache --spider -S http://localhost:${local.container_ports.reporting}/reports/healthcheck || exit 1"
    }
    "replace-service" = {
      reporting_protocol             = "HTTPS"
      reporting_protocol_version     = "HTTP2"
      web_protocol_version           = "HTTP2"
      web_temp_priority              = 49400
      web_temp_test_priority         = 19
      reporting_temp_priority        = 48000
      reporting_temp_test_priority   = 14
      reporting_service_health_check = "wget --no-cache --spider -S --no-check-certificate https://localhost:${local.container_ports.reporting}/reports/healthcheck || exit 1"
    }
    "switch-traffic-back-to-original" = {
      reporting_protocol             = "HTTPS"
      reporting_protocol_version     = "HTTP2"
      web_protocol_version           = "HTTP2"
      web_temp_priority              = 49505
      web_temp_test_priority         = 21
      reporting_temp_priority        = 49005
      reporting_temp_test_priority   = 16
      reporting_service_health_check = "wget --no-cache --spider -S --no-check-certificate https://localhost:${local.container_ports.reporting}/reports/healthcheck || exit 1"
    }
  }
}


############# Temporary migration services #############


module "web_service_temp" {
  count           = var.temporary_migration_resources_active ? 1 : 0
  container_image = var.HTTP2_compatible_web_image
  source          = "./modules/ecs_service"
  task_config = {
    environment          = local.web_envs
    secrets              = local.task_secrets["CORE"]
    cpu                  = 2048
    memory               = 4096
    execution_role_arn   = aws_iam_role.ecs_task_execution_role["CORE"].arn
    task_role_arn        = data.aws_iam_role.ecs_task_role.arn
    log_group_name       = aws_cloudwatch_log_group.ecs_log_group.name
    region               = var.region
    health_check_command = ["CMD-SHELL", "./bin/internal_healthcheck http://localhost:${local.container_ports.web}/health/database"]
  }
  network_params = {
    subnets = [aws_subnet.private_subnet_a.id, aws_subnet.private_subnet_b.id]
    vpc_id  = aws_vpc.application_vpc.id
  }
  loadbalancer = {
    target_group_blue            = aws_lb_target_group.web_blue_temp[0].arn
    target_group_green           = aws_lb_target_group.web_green_temp[0].arn
    container_port               = local.container_ports.web
    production_listener_rule_arn = aws_lb_listener_rule.forward_to_app_temp[0].arn
    test_listner_rule_arn        = aws_lb_listener_rule.forward_to_test_temp[0].arn
    deploy_role_arn              = aws_iam_role.ecs_deploy.arn
  }
  autoscaling_policies = tomap({
    cpu = {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
      target_value           = 60
      scale_in_cooldown      = 600
      scale_out_cooldown     = 300
    }
  })
  cluster_id            = aws_ecs_cluster.cluster.id
  cluster_name          = aws_ecs_cluster.cluster.name
  minimum_replica_count = var.minimum_web_replicas
  maximum_replica_count = var.maximum_web_replicas
  environment           = var.environment
  server_type           = "web"
  server_type_name      = "web-temp"
  service_connect_config = {
    namespace = aws_service_discovery_private_dns_namespace.internal.arn
    services = [
      {
        port_name      = "web-port"
        discovery_name = "web_temp"
        port           = local.container_ports.web
        dns_name       = "web_temp"
      }
    ]
  }

  depends_on = [
    aws_iam_role.ecs_deploy,
    aws_rds_cluster_instance.core,
    aws_elasticache_replication_group.valkey
  ]
}

module "reporting_service_temp" {
  count           = var.temporary_migration_resources_active ? 1 : 0
  container_image = var.HTTP2_compatible_reporting_image
  source          = "./modules/ecs_service"
  task_config = {
    environment = concat(
      [ # Terraform loop to take local.task_envs["REPORTING"] and overwrite the HTTP_MODE variable to be HTTPS
        for env_var in local.task_envs["REPORTING"] : env_var.name == "HTTP_MODE" ? {
          name  = env_var.name
          value = "HTTPS"
        } : env_var
      ],
      [{ # The reporting service needs to be able to reach the web service at the web_temp hostname during migration
        name  = "MAVIS_ROOT_URL",
        value = "http://web_temp:4000/"
      }]
    )
    secrets              = local.task_secrets["REPORTING"]
    cpu                  = 1024
    memory               = 2048
    execution_role_arn   = aws_iam_role.ecs_task_execution_role["REPORTING"].arn
    task_role_arn        = data.aws_iam_role.ecs_task_role.arn
    log_group_name       = aws_cloudwatch_log_group.ecs_log_group.name
    region               = var.region
    health_check_command = ["CMD-SHELL", "wget --no-cache --spider -S --no-check-certificate https://localhost:${local.container_ports.reporting}/reports/healthcheck || exit 1"]
  }
  network_params = {
    subnets = [aws_subnet.private_subnet_a.id, aws_subnet.private_subnet_b.id]
    vpc_id  = aws_vpc.application_vpc.id
  }
  loadbalancer = {
    target_group_blue            = aws_lb_target_group.reporting_blue_temp[0].arn
    target_group_green           = aws_lb_target_group.reporting_green_temp[0].arn
    container_port               = local.container_ports.reporting
    production_listener_rule_arn = aws_lb_listener_rule.forward_to_reporting_temp[0].arn
    test_listner_rule_arn        = aws_lb_listener_rule.forward_to_reporting_test_temp[0].arn
    deploy_role_arn              = aws_iam_role.ecs_deploy.arn
  }
  autoscaling_policies = tomap({
    cpu = {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
      target_value           = 60
      scale_in_cooldown      = 600
      scale_out_cooldown     = 300
    }
  })
  container_port        = local.container_ports.reporting
  minimum_replica_count = var.minimum_reporting_replicas
  maximum_replica_count = var.maximum_reporting_replicas
  cluster_id            = aws_ecs_cluster.cluster.id
  cluster_name          = aws_ecs_cluster.cluster.name
  environment           = var.environment
  server_type           = "reporting"
  server_type_name      = "reporting-temp"
  service_connect_config = {
    namespace = aws_service_discovery_private_dns_namespace.internal.arn
    services  = []
  }

  depends_on = [
    aws_iam_role.ecs_deploy
  ]
}

########### Temporary service security groups and security group rules #############


resource "aws_security_group_rule" "web_temp_service_alb_ingress" {
  count                    = var.temporary_migration_resources_active ? 1 : 0
  type                     = "ingress"
  from_port                = local.container_ports.web
  to_port                  = local.container_ports.web
  protocol                 = "tcp"
  security_group_id        = module.web_service_temp[0].security_group_id
  source_security_group_id = aws_security_group.lb_service_sg.id
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "reporting_temp_service_alb_ingress" {
  count                    = var.temporary_migration_resources_active ? 1 : 0
  type                     = "ingress"
  from_port                = local.container_ports.reporting
  to_port                  = local.container_ports.reporting
  protocol                 = "tcp"
  security_group_id        = module.reporting_service_temp[0].security_group_id
  source_security_group_id = aws_security_group.lb_service_sg.id
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "reporting_temp_to_web_temp" {
  count                    = var.temporary_migration_resources_active ? 1 : 0
  type                     = "ingress"
  from_port                = local.container_ports.web
  to_port                  = local.container_ports.web
  protocol                 = "tcp"
  security_group_id        = module.web_service_temp[0].security_group_id
  source_security_group_id = module.reporting_service_temp[0].security_group_id
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "rds_web_temp_ingress" {
  count                    = var.temporary_migration_resources_active ? 1 : 0
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rds_security_group.id
  source_security_group_id = module.web_service_temp[0].security_group_id
  lifecycle {
    create_before_destroy = true
  }
}


############# Temporary ALB listeners/target groups #############





resource "aws_lb_target_group" "web_blue_temp" {
  count            = var.temporary_migration_resources_active ? 1 : 0
  name             = "blue-${var.environment}"
  port             = local.container_ports.web
  protocol         = "HTTP"
  protocol_version = "HTTP2"
  vpc_id           = aws_vpc.application_vpc.id
  target_type      = "ip"
  health_check {
    path                = "/up"
    protocol            = "HTTP"
    port                = "traffic-port"
    matcher             = "200"
    interval            = 5
    timeout             = 4
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_target_group" "web_green_temp" {
  count            = var.temporary_migration_resources_active ? 1 : 0
  name             = "green-${var.environment}"
  port             = local.container_ports.web
  protocol         = "HTTP"
  protocol_version = "HTTP2"
  vpc_id           = aws_vpc.application_vpc.id
  target_type      = "ip"
  health_check {
    path                = "/up"
    protocol            = "HTTP"
    port                = "traffic-port"
    matcher             = "200"
    interval            = 5
    timeout             = 4
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_target_group" "reporting_blue_temp" {
  count            = var.temporary_migration_resources_active ? 1 : 0
  name             = "rep-blue-${var.environment}"
  port             = local.container_ports.reporting
  protocol         = "HTTPS"
  protocol_version = "HTTP2"
  vpc_id           = aws_vpc.application_vpc.id
  target_type      = "ip"
  health_check {
    path                = "/reports/healthcheck"
    protocol            = "HTTPS"
    port                = "traffic-port"
    matcher             = "200"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_target_group" "reporting_green_temp" {
  count            = var.temporary_migration_resources_active ? 1 : 0
  name             = "rep-green-${var.environment}"
  port             = local.container_ports.reporting
  protocol         = "HTTPS"
  protocol_version = "HTTP2"
  vpc_id           = aws_vpc.application_vpc.id
  target_type      = "ip"
  health_check {
    path                = "/reports/healthcheck"
    protocol            = "HTTPS"
    port                = "traffic-port"
    matcher             = "200"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener_rule" "forward_to_app_temp" {
  count        = var.temporary_migration_resources_active ? 1 : 0
  listener_arn = aws_lb_listener.app_listener_https.arn
  priority     = local.migration_stage_configs[var.migration_stage].web_temp_priority
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_blue_temp[0].arn
  }
  condition {
    path_pattern {
      values = ["/*"]
    }
  }
  condition {
    host_header {
      values = local.host_headers
    }
  }

  lifecycle {
    ignore_changes = [action]
  }
}

resource "aws_lb_listener_rule" "forward_to_test_temp" {
  count        = var.temporary_migration_resources_active ? 1 : 0
  listener_arn = aws_lb_listener.app_listener_https.arn
  priority     = local.migration_stage_configs[var.migration_stage].web_temp_test_priority

  # Action to forward traffic to the target group
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_green_temp[0].arn
  }

  # Condition based on HTTP header
  condition {
    http_header {
      http_header_name = "X-Environment"
      values           = ["test"]
    }
  }
  lifecycle {
    ignore_changes = [action]
  }
}

resource "aws_lb_listener_rule" "forward_to_reporting_temp" {
  count        = var.temporary_migration_resources_active ? 1 : 0
  listener_arn = aws_lb_listener.app_listener_https.arn
  priority     = local.migration_stage_configs[var.migration_stage].reporting_temp_priority
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.reporting_blue_temp[0].arn
  }
  condition {
    path_pattern {
      values = var.reporting_endpoints
    }
  }
  condition {
    host_header {
      values = local.host_headers
    }
  }

  lifecycle {
    ignore_changes = [action]
  }
}

resource "aws_lb_listener_rule" "forward_to_reporting_test_temp" {
  count        = var.temporary_migration_resources_active ? 1 : 0
  listener_arn = aws_lb_listener.app_listener_https.arn
  priority     = local.migration_stage_configs[var.migration_stage].reporting_temp_test_priority
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.reporting_green_temp[0].arn
  }
  condition {
    path_pattern {
      values = var.reporting_endpoints
    }
  }
  condition {
    host_header {
      values = local.host_headers
    }
  }

  condition {
    http_header {
      http_header_name = "X-Environment"
      values           = ["test"]
    }
  }
  lifecycle {
    ignore_changes = [action]
  }
}