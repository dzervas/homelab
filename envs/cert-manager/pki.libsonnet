local cm = import 'cert-manager-libsonnet/1.19/main.libsonnet';
local certificate = cm.nogroup.v1.certificate;
local issuer = cm.nogroup.v1.issuer;

local namespace = 'cert-manager';
local domain = 'dzerv.art';

local certDuration = '87658h0m0s';  // 10 years
local domains = [
  domain,
  'staging.blogaki.io',
  'staging.dzerv.it',
  '*.' + domain,
  '*.staging.blogaki.io',
];

// Guest certificates with specific FQDNs
local guests = {
  psof: ['auto.' + domain],  // n8n fqdn
};

// Private key settings for client certificates
local privateKeySpec = {
  algorithm: 'ECDSA',
  size: 384,
};

// Client certificate template
local clientCertificate(name, dnsNames, secretName=null) =
  certificate.new('client-' + name)
  + certificate.metadata.withNamespace(namespace)
  + certificate.spec.withSecretName(if secretName != null then secretName else 'client-' + name + '-certificate')
  + certificate.spec.withDnsNames(dnsNames)
  + certificate.spec.withDuration(certDuration)
  + certificate.spec.privateKey.withAlgorithm(privateKeySpec.algorithm)
  + certificate.spec.privateKey.withSize(privateKeySpec.size)
  + certificate.spec.withUsages(['server auth', 'client auth'])
  + certificate.spec.issuerRef.withName('client-ca')
  + certificate.spec.issuerRef.withKind('Issuer');

{
  // Client CA certificate (self-signed)
  clientCa:
    certificate.new('client-ca')
    + certificate.metadata.withNamespace(namespace)
    + certificate.spec.withSecretName('client-ca-certificate')
    + certificate.spec.withDnsNames(domains)
    + certificate.spec.subject.withOrganizations([domain])
    + certificate.spec.withDuration(certDuration)
    + certificate.spec.privateKey.withAlgorithm(privateKeySpec.algorithm)
    + certificate.spec.privateKey.withSize(privateKeySpec.size)
    + certificate.spec.withIsCA(true)
    + certificate.spec.issuerRef.withName('selfsigned')
    + certificate.spec.issuerRef.withKind('ClusterIssuer'),

  // Client CA issuer (uses the client-ca certificate)
  clientCaIssuer:
    issuer.new('client-ca')
    + issuer.metadata.withNamespace(namespace)
    + issuer.spec.ca.withSecretName('client-ca-certificate'),

  // Client certificates for devices
  clientDesktop: clientCertificate('desktop', domains),
  clientLaptop: clientCertificate('laptop', domains),
  clientMobile: clientCertificate('mobile', domains),

  // Guest certificates
  clientGuestPsof: clientCertificate('guest-psof', guests.psof),
}
