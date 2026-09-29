# Catch-all proxy — forwards every path/method through the VPC Link to the NLB, which forwards to
# thor. The stage (deployment.tf) is named, not $default, so it's a real leading path segment on
# every request that reaches this API — including through CloudFront, whose origin_path (cdn.tf)
# prepends it to every request regardless of environment. thor.api's own routing knows nothing
# about API Gateway stages, so request_parameters rewrites the outgoing path to strip it before
# forwarding (e.g. "/dev/v1/orders" -> "/v1/orders").
#
# Two integrations, not one, because the rewrite expression differs per route: the proxy route's
# $request.path.proxy only resolves against its own {proxy+} capture, and referencing it from the
# root route (which has no such parameter) is invalid.

resource "aws_apigatewayv2_integration" "proxy" {
  api_id = aws_apigatewayv2_api.thor-apigw-api.id

  integration_type       = "HTTP_PROXY"
  integration_method     = "ANY"
  connection_type        = "VPC_LINK"
  connection_id          = aws_apigatewayv2_vpc_link.thor-apigw-vpclink.id
  integration_uri        = var.nlb_listener_arn
  payload_format_version = "1.0"

  # X-THOR-TENANT-ID comes from the authorizer's verified context, never the client.
  request_parameters = {
    "overwrite:path"                    = "/$request.path.proxy"
    "overwrite:header.X-THOR-TENANT-ID" = "$context.authorizer.tenant_id"
  }

  # Must agree with the NLB's own TLS state — plain HTTP unless a real cert is configured there too.
  dynamic "tls_config" {
    for_each = var.tls_server_name != "" ? [1] : []
    content {
      server_name_to_verify = var.tls_server_name
    }
  }
}

resource "aws_apigatewayv2_integration" "proxy_root" {
  api_id = aws_apigatewayv2_api.thor-apigw-api.id

  integration_type       = "HTTP_PROXY"
  integration_method     = "ANY"
  connection_type        = "VPC_LINK"
  connection_id          = aws_apigatewayv2_vpc_link.thor-apigw-vpclink.id
  integration_uri        = var.nlb_listener_arn
  payload_format_version = "1.0"

  request_parameters = {
    "overwrite:path"                    = "/"
    "overwrite:header.X-THOR-TENANT-ID" = "$context.authorizer.tenant_id"
  }

  dynamic "tls_config" {
    for_each = var.tls_server_name != "" ? [1] : []
    content {
      server_name_to_verify = var.tls_server_name
    }
  }
}

resource "aws_apigatewayv2_route" "proxy_root" {
  api_id    = aws_apigatewayv2_api.thor-apigw-api.id
  route_key = "ANY /"
  target    = "integrations/${aws_apigatewayv2_integration.proxy_root.id}"

  authorization_type = "CUSTOM"
  authorizer_id      = aws_apigatewayv2_authorizer.thor-api-key.id
}

resource "aws_apigatewayv2_route" "proxy" {
  api_id    = aws_apigatewayv2_api.thor-apigw-api.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.proxy.id}"

  authorization_type = "CUSTOM"
  authorizer_id      = aws_apigatewayv2_authorizer.thor-api-key.id
}
