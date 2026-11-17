# Custom domains on the production app (var.custom_domains), each with an Azure-managed certificate that the
# environment renews on its own. The DNS records stay at the registrar, outside this module: an A record for an apex
# (to output.environment_static_ip) or a CNAME for a subdomain (to the app's hostname), plus an asuid TXT record for
# each name, valued output.custom_domain_verification_id. TXT validation also needs a _dnsauth TXT record with the
# certificate's validation token.
#
# The provider can create the certificate and the hostname but can't attach one to the other, so a domain is bound
# with az first and then imported (README, "Custom domains"). With TXT validation that works before DNS points at the
# app: bind ahead of time, then switch DNS with no certificate errors (tested 2026-11-17).

resource "azurerm_container_app_environment_managed_certificate" "production" {
  for_each = var.custom_domains

  name                         = each.value.certificate_name
  container_app_environment_id = local.environment_id
  subject_name                 = each.key
  # azurerm 5.x accepts only CNAME and HTTP here, though Azure also issues with TXT. The certificate is created by az
  # and imported, so the value is only a placeholder for TXT, and later differences are ignored rather than forcing a
  # replacement.
  domain_control_validation = each.value.validation == "TXT" ? "HTTP" : each.value.validation

  # Replacing a live site's certificate would take the domain off HTTPS until Azure issues a new one.
  lifecycle {
    prevent_destroy = true
    ignore_changes  = [domain_control_validation]
  }
}

resource "azurerm_container_app_custom_domain" "production" {
  for_each = var.custom_domains

  name             = each.key
  container_app_id = azurerm_container_app.production.id

  lifecycle {
    # The binding to an Azure-managed certificate is made through the managed-certificate API, which this resource
    # doesn't model. The provider documents ignoring these two, or every plan would try to rebuild the binding.
    ignore_changes = [certificate_binding_type, container_app_environment_certificate_id]
  }

  depends_on = [azurerm_container_app_environment_managed_certificate.production]
}
