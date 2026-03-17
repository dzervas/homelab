local dockerService = import 'docker-service.libsonnet';
local timezone = import 'helpers/timezone.libsonnet';
local lab = import 'labsonnet.libsonnet';

lab.new('atuin', 'ghcr.io/atuinsh/atuin')
+ lab.withCreateNamespace()
+ lab.withType('StatefulSet')
+ lab.withArgs(['start'])
+ lab.withPV('/db', { name: 'db', size: '1Gi' })
+ lab.withVpnHttp(8888, 'sh.vpn.dzerv.art')
+ lab.withEnv({
  ATUIN_HOST: '0.0.0.0',
  ATUIN_PORT: '8888',
  ATUIN_OPEN_REGISTRATION: 'false',
  ATUIN_DB_URI: 'sqlite:///db/atuin.db',
  RUST_LOG: 'info',  // "info,atuin_server=debug"
  TZ: timezone,
})
