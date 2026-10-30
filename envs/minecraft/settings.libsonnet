{
  minecraftVersion: '1.21.1',
  neoForgeVersion: '21.1.265',
  imageTag: 'java21',
  providers: ['oracle'],
  storageClass: 'longhorn-v1',
  storageSize: '10Gi',
  // A fresh claim, deliberately distinct from the old Fabric release's data volume
  worldClaim: 'minecraft-neoforge-world',
  metricsInterval: '15s',

  motd: "I'm a form of art",
  icon: 'https://github.com/dzervas/dzervas/raw/main/assets/images/logo.svg',
  difficulty: 'normal',
  viewDistance: 32,
  simulationDistance: 16,
  initialMemory: '4G',
  maximumMemory: '12G',
  // Heap excludes native/JVM overhead
  memoryRequest: '4Gi',
  memoryLimit: '14Gi',

  ops: [
    'dzervasgr',
    'looselyrigorous',
    'Raffle_Daffle',
    'Hendog2014',
  ],
  whitelist: [
    'dzervasgr',
    'gkaklas',
    'chinesium_',
    'looselyrigorous',
    'Raffle_Daffle',  // Ortiz
    'Hendog2014',  // Ortiz's friend
    'kingsilicon',
    'KayItzSam',
  ],
  startupCommands: [
    'gamerule playersSleepingPercentage 1',
    // The old connection hook used these teams without creating them on a fresh world
    'team add new',
    'team add old',
  ],
  starterItems: [
    'minecraft:stone_axe',
    'minecraft:stone_pickaxe',
    'minecraft:crafting_table',
    'minecraft:cooked_porkchop 8',
    'minecraft:bow',
    'minecraft:arrow 64',
  ],

  backpackRows: 6,
  graveProtectionDays: 7,
  graveExpirationDays: 7,
  graveXpPercentage: 100,

  backups: {
    enabled: true,
    interval: '6h',
    initialDelay: '2h',
    repository: 'rclone:remote:/rclone/backups/minecraft',
    // Isolate this fresh world's retention group from the old world's snapshots
    hostname: 'minecraft-' + $.minecraftVersion,
    name: 'minecraft-' + $.minecraftVersion,
  },

  // Preserve the server-side selections from .github/modpack; client-only mods stay client-side
  // Version IDs pin the selected artifacts, including intentionally selected beta releases
  modrinthVersions: {
    appleskin: 'uAKA6Laj',  // 3.0.9
    'architectury-api': '1IiqEQGl',  // 13.0.11
    create: 'UjX6dr61',  // 6.0.10
    'create-goggles': 'Co24W2FL',  // 6.1.1
    'create-power-loader': '3Y4r0ItR',  // 2.0.5
    jade: 'eYz2YBGT',  // 15.10.6
    'jade-addons-forge': 'O3F6Dkle',  // 6.1.2
    jei: 'j41QZiGx',  // 19.70.0.468
    mezzconfig: 'sL7Ghaz1',  // 0.6.10
    lithium: 'DDUrRVCA',  // 0.15.4
    'ping-wheel': 'Zrh2Fmn9',  // 1.12.2
    'xaeros-minimap': 'irjR7dHk',  // 26.6.0

    // NeoForge continuations of the old gameplay, plus explicit dependencies
    storagedrawers: 'px0CCB06',  // 13.11.4
    'elytra-slot': 'RX6A02W1',  // 9.0.2
    curios: 'yohfFbgD',  // 9.5.1
    caelus: 'KsfI4QsR',  // 7.0.1
    'create-garnished': 'EKUHxs6i',  // 2.1.9.2
    chipped: 'eqVowbGc',  // 4.0.2
    'resourceful-lib': 'x99nCLTm',  // 3.0.12
    spark: 'v5qtqRQi',  // 1.10.124

    // Replace Fabric-only Universal Graves and Convenient MobGriefing
    yigd: 'Axk4bfXT',  // 2.0.13
    'cloth-config': 'izKINKFg',  // 15.0.140
    'more-mobgriefing-options': 'ElBlQzD1',  // 3.0.2
  },
  curseForgeFiles: {
    backpacked: 7866688,  // 3.0.5
    framework: 7530361,  // 0.13.11
    // The Modrinth project with this slug is an unrelated plugin
    'prometheus-exporter': 5657655,  // 1.2.1, native NeoForge
  },
}
