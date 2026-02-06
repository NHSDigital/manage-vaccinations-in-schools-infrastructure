# Updating ECS service (aws_ecs_service) or ALB target groups (aws_lb_target_group)

## Why do we need a unique deployment process services

Some changes are only possible to achieve by recreating the service. The naive Terraform approach of deleting and
recreating the service is not possible because the service's deployment is controlled by ECS Blue/Green deploy,
this is a built-in safety mechanism. Additionally, even if we can circumvent this blocker to deployment recreating
the service would cause a downtime which can easily be avoided by following the below steps.

## Safer Migration Strategy Using Temporary Resources

Direct modifications to target groups during blue/green deployments carry significant rollback risks where the system can
end up in a mixed state with traffic served both on blue and green target groups. In this situation forward fixing becomes
very difficult and the risk of down time increases significantly. Our approach uses temporary ALB/ECS resources controlled
through listener rule priorities to ensure a zero down-time deployment process.

For implementation details and template configuration, see:
[Service Migration Temporary Resources Template](../resources/service_migration_temporary_resources.template.tf)

### Migration Stages

1. **pre-migration-1**:

   - Apply any non-migration changes
   - Original services remain fully operational
   - Configured via
     - `temporary_migration_resources_active=false`
     - `migration_stage="pre-migration"`

1. **pre-migration-2**:

   - Creates temporary services (`web_service_temp`, `reporting_service_temp`) with listener rules at non-active priorities
   - Original services remain fully operational
   - Configured via
     - `temporary_migration_resources_active=true`
     - `migration_stage="pre-migration"`

1. **switch-traffic-to-temp**:

   - Updates listener rule priorities to route traffic to temporary services
   - Original services remain deployed but inactive
   - Configured via
     - `temporary_migration_resources_active=true`
     - `migration_stage="switch-traffic-to-temp"`

1. **replace-service**:

   - Deploys HTTP2-compatible versions to original services
   - Maintains traffic routing to temporary services during transition
   - Original services are replaced without serving any traffic
   - Configured via
     - `temporary_migration_resources_active=true`
     - `migration_stage="replace-service"`
   - Here we will also need to use the `-replace` terraform option on any relevant services/target groups/listener rules. For example:
     ```
     -replace module.web_service.aws_ecs_service.this -replace aws_lb_listener_rule.forward_to_app -replace aws_lb_listener_rule.forward_to_test
     ```

1. **switch-traffic-back-to-original**:

   - Shifts traffic back to upgraded original services
   - Decommissions temporary resources
   - Configured via
     - `temporary_migration_resources_active=true`
     - `migration_stage="switch-traffic-back-to-original"`

1. **post-migration**:

   - Removes temporary services/resources
   - Recreated service continues to serve traffic uninterrupted
   - Configured via
     - `temporary_migration_resources_active=false`
     - `migration_stage="switch-traffic-back-to-original"`

### Traffic Control Mechanism

- Listener rule priorities control routing (lower numbers = higher priority)
- Each stage modifies priorities in `local.migration_stage_configs`
- Priority changes enable seamless traffic shifts without target group modifications
- The setup is structured in such a way that only the priorities of the temporary listeners are adjusted up/down keeping the original service listeners' priorities unmodified

### Terraform Implementation

Key resources in \[app/http1_to_http2_migration_resources.tf\]:

- `aws_lb_listener_rule.forward_to_*_temp` - Temporary routing rules
- `module.web_service_temp` - Temporary ECS service
- `local.migration_stage_configs` - Stage-specific priority configurations

This approach eliminates direct target group modifications, ensuring clean rollbacks by simply reverting priority changes.
