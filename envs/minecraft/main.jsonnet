local datapacks = import './datapacks.libsonnet';
local modConfig = import './mod-config.libsonnet';
local secrets = import './secrets.libsonnet';
local settings = import './settings.libsonnet';
local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local affinity = import 'helpers/affinity.libsonnet';
local timezone = import 'helpers/timezone.libsonnet';
local k = import 'k.libsonnet';
local prometheus = import 'prometheus-operator-libsonnet/0.86/main.libsonnet';

local helm = tk.helm.new(std.thisFile);
local configMap = k.core.v1.configMap;
local pvc = k.core.v1.persistentVolumeClaim;
local networkPolicy = k.networking.v1.networkPolicy;
local serviceMonitor = prometheus.monitoring.v1.serviceMonitor;

local namespace = 'minecraft';
local configFiles = modConfig.files + datapacks;
local fileKey(path) = std.strReplace(path, '/', '_');

{
  namespace: k.core.v1.namespace.new(namespace),

  world:
    pvc.new(settings.worldClaim)
    + pvc.spec.withAccessModes(['ReadWriteOnce'])
    + pvc.spec.withStorageClassName(settings.storageClass)
    + pvc.spec.resources.withRequests({ storage: settings.storageSize }),

  config:
    configMap.new('minecraft-config')
    + configMap.withData({
      [fileKey(path)]: configFiles[path]
      for path in std.objectFields(configFiles)
    }),

  minecraft:
    helm.template('minecraft', '../../charts/minecraft', {
      namespace: namespace,
      values: {
        fullnameOverride: 'minecraft',
        image: { tag: settings.imageTag },
        affinity: affinity.requireProviders(settings.providers),
        podAnnotations: { 'checksum/config': std.md5(std.manifestJson(configFiles)) },
        resources: {
          requests: { memory: settings.memoryRequest, cpu: '1' },
          limits: { memory: settings.memoryLimit, cpu: '4' },
        },
        persistence: {
          dataDir: { enabled: true, existingClaim: settings.worldClaim },
        },
        // Preserve the old server's tolerance of long modded ticks without probe-triggered restarts
        livenessProbe: { command: ['true'], initialDelaySeconds: 1, periodSeconds: 20, failureThreshold: 30 },
        readinessProbe: { command: ['true'], initialDelaySeconds: 1, periodSeconds: 20, failureThreshold: 30 },
        terminationGracePeriodSeconds: 120,

        minecraftServer: {
          eula: 'TRUE',
          type: 'NEOFORGE',
          version: settings.minecraftVersion,
          memory: settings.maximumMemory,
          motd: settings.motd,
          icon: settings.icon,
          difficulty: settings.difficulty,
          onlineMode: true,
          spawnProtection: 0,
          overrideServerProperties: true,
          ops: std.join(',', settings.ops),
          whitelist: std.join(',', settings.whitelist),
          serviceType: 'NodePort',
          nodePort: 25565,
          maxTickTime: -1,
          viewDistance: settings.viewDistance,
          autoCurseForge: {
            apiKey: { existingSecret: 'minecraft-op', secretKey: 'curseforge-api-key' },
          },
          modrinth: {
            projects: [
              project + ':' + settings.modrinthVersions[project]
              for project in std.objectFields(settings.modrinthVersions)
            ],
            // Dependencies are explicitly pinned alongside their parent mods
            downloadDependencies: 'none',
            allowedVersionType: 'beta',
          },
          rcon: { enabled: true, existingSecret: 'minecraft-rcon' },
          extraPorts: [{
            name: 'prometheus',
            containerPort: 19565,
            protocol: 'TCP',
            service: { enabled: true, embedded: false, type: 'ClusterIP', port: 19565 },
          }],
        },

        // File subPath mounts avoid copying Kubernetes' ConfigMap directory symlinks
        // Use the image's supported config sync, not a custom init script or generated ZIPs
        extraVolumes: [{
          volumes: [{ name: 'config', configMap: { name: 'minecraft-config' } }],
          volumeMounts: [
            { name: 'config', mountPath: '/config/' + path, subPath: fileKey(path), readOnly: true }
            for path in std.objectFields(configFiles)
          ],
        }],

        mcbackup: {
          enabled: settings.backups.enabled,
          image: { pullPolicy: 'Always' },
          backupMethod: 'restic',
          backupInterval: settings.backups.interval,
          initialDelay: settings.backups.initialDelay,
          backupName: settings.backups.name,
          resticHostname: settings.backups.hostname,
          resticRepository: settings.backups.repository,
          resticAdditionalTags: 'mc_backups ' + namespace,
          // The chart copies this to writable storage so rclone can refresh its OneDrive token
          // Refreshed tokens are Pod-local; keep the source 1Password token valid across restarts
          rcloneConfigExistingSecret: 'minecraft-op',
          resticEnvs: {
            RESTIC_PASSWORD: { valueFrom: { secretKeyRef: { name: 'minecraft-op', key: 'restic-password' } } },
          },
          extraEnv: {
            PRE_SAVE_ALL_SCRIPT: |||
              rcon-cli tellraw @a '[{"text":"Server will lag/time out in "},{"text":"30 seconds","bold":true,"underlined":true,"color":"yellow"},{"text":" to take backup"}]'
              sleep 30
              rcon-cli say 'Server saving the world to start the backup'
            |||,
            PRE_BACKUP_SCRIPT: "rcon-cli say 'Done, starting backup. Lag should stop'",
            POST_BACKUP_SCRIPT: "rcon-cli say 'Backup done!'",
            TZ: timezone,
          },
        },

        extraEnv: {
          NEOFORGE_VERSION: settings.neoForgeVersion,
          CURSEFORGE_FILES: std.join(',', [
            project + ':' + std.toString(settings.curseForgeFiles[project])
            for project in std.objectFields(settings.curseForgeFiles)
          ]),

          ENABLE_WHITELIST: 'TRUE',
          ENFORCE_WHITELIST: 'TRUE',
          // Treat the Jsonnet lists as authoritative, including removals
          EXISTING_OPS_FILE: 'SYNCHRONIZE',
          EXISTING_WHITELIST_FILE: 'SYNCHRONIZE',
          RCON_CMDS_STARTUP: std.join('\n', settings.startupCommands + modConfig.startupCommands),
          RCON_CMDS_ON_CONNECT: std.join(
            '\n',
            ['team join new @a[team=]']
            + ['give @a[team=new] ' + item for item in settings.starterItems]
            + ['team join old @a[team=new]']
          ),

          COPY_CONFIG_DEST: '/data',
          SYNC_SKIP_NEWER_IN_DESTINATION: 'false',
          ALLOW_FLIGHT: 'TRUE',
          SNOOPER_ENABLED: 'FALSE',
          INIT_MEMORY: settings.initialMemory,
          MAX_MEMORY: settings.maximumMemory,
          SIMULATION_DISTANCE: std.toString(settings.simulationDistance),
          SYNC_CHUNK_WRITES: 'FALSE',
          DISABLE_HEALTHCHECK: 'TRUE',
          TZ: timezone,
        },
      },
    }),

  ingress:
    networkPolicy.new('minecraft-ingress')
    + networkPolicy.spec.podSelector.withMatchLabels({ app: 'minecraft' })
    + networkPolicy.spec.withPolicyTypes(['Ingress'])
    + networkPolicy.spec.withIngress([
      {
        from: [{ ipBlock: { cidr: '0.0.0.0/0' } }],
        ports: [{ port: 25565, protocol: 'TCP' }],
      },
      {
        from: [{ namespaceSelector: { matchLabels: { 'kubernetes.io/metadata.name': 'k8s-monitoring' } } }],
        ports: [{ port: 19565, protocol: 'TCP' }],
      },
    ]),

  // Fleet owns ServiceMonitor discovery; verify live scraping after deployment
  metrics:
    serviceMonitor.new('minecraft-exporter')
    + serviceMonitor.spec.selector.withMatchLabels({ app: 'minecraft-prometheus' })
    + serviceMonitor.spec.namespaceSelector.withMatchNames([namespace])
    + serviceMonitor.spec.withEndpoints([{ port: 'prometheus', interval: settings.metricsInterval }]),
} + secrets
