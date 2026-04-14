module "mock_careplus_service" {
  count  = var.enable_mock_careplus_service ? 1 : 0
  source = "./modules/ecs_service"

  environment  = var.environment
  server_type  = "mock-careplus"
  cluster_id   = aws_ecs_cluster.cluster.id
  cluster_name = aws_ecs_cluster.cluster.name
  network_params = {
    subnets = [aws_subnet.private_subnet_a.id, aws_subnet.private_subnet_b.id]
    vpc_id  = aws_vpc.application_vpc.id
  }
  task_config = {
    environment = [
      {
        name  = "SENTRY_ENVIRONMENT"
        value = var.environment
      }
    ]
    secrets              = []
    cpu                  = 256
    memory               = 512
    execution_role_arn   = aws_iam_role.ecs_task_execution_role["CORE"].arn
    task_role_arn        = data.aws_iam_role.ecs_task_role.arn
    log_group_name       = aws_cloudwatch_log_group.ecs_log_group.name
    region               = var.region
    health_check_command = ["CMD-SHELL", "python -c \"from urllib.request import urlopen; urlopen('http://127.0.0.1:8080/health').read()\" || exit 1"]
  }
  minimum_replica_count = 1
  maximum_replica_count = 1
  port_mappings = [
    {
      name          = "mock-careplus-port"
      containerPort = local.container_ports.mock_careplus
      appProtocol   = "http"
    }
  ]
  service_connect_config = {
    namespace = aws_service_discovery_private_dns_namespace.internal.arn
    services = [
      {
        port_name      = "mock-careplus-port"
        discovery_name = "mock-careplus"
        port           = local.container_ports.mock_careplus
        dns_name       = "mock-careplus"
      }
    ]
  }
}

resource "aws_security_group_rule" "web_to_mock_careplus" {
  count                    = var.enable_mock_careplus_service ? 1 : 0
  type                     = "ingress"
  from_port                = local.container_ports.mock_careplus
  to_port                  = local.container_ports.mock_careplus
  protocol                 = "tcp"
  security_group_id        = module.mock_careplus_service[0].security_group_id
  source_security_group_id = module.web_service.security_group_id
  lifecycle {
    create_before_destroy = true
  }
}
