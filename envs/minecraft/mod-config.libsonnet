local settings = import './settings.libsonnet';

{
  startupCommands: ['gamerule mobGriefing false'],
  files: {
    'config/yigd.json': std.manifestJsonEx({
      expConfig: {
        dropBehaviour: 'PERCENTAGE',
        dropPercentage: settings.graveXpPercentage,
        keepPercentage: 0,
      },
      graveConfig: {
        enabled: true,
        storeItems: true,
        storeXp: true,
        requireShovelToLoot: false,
        retrieveMethods: { onClick: true, onBreak: false, onSneak: false, onStand: false },
        dropOnRetrieve: 'IN_INVENTORY',
        claimPriority: 'GRAVE',
        graveRobbing: {
          enabled: true,
          killerSkipWaitTime: false,
          afterTime: settings.graveProtectionDays,
          timeUnit: 'DAYS',
        },
        // Both timers start at death and count world ticks, not server downtime
        // Unlike Universal Graves, YIGD executes expiry only when the grave's chunk is ticking
        graveTimeout: {
          enabled: true,
          afterTime: settings.graveExpirationDays,
          timeUnit: 'DAYS',
          dropContentsOnTimeout: true,
        },
      },
    }, '  '),

    'config/backpacked.backpack.toml': std.manifestTomlEx({
      inventory: {
        size: { columns: 9, rows: settings.backpackRows },
        slots: {
          unlockAllSlots: false,
          initialUnlockedSlots: 9,
          allowUnlockingUsingUnlockToken: true,
        },
      },
    }, '  '),
    // Disables player theft; the wandering-trader challenge remains part of progression
    'config/backpacked.pickpocketing.toml': std.manifestTomlEx({ enabledPickpocketing: false }, '  '),

    // MMGO 3.0.2 really generates two nested mobGriefing tables; values are enum strings
    // Other entities follow the false vanilla gamerule, while villagers can farm and pick up food
    'config/moremobgriefingoptions-server.toml': std.manifestTomlEx({
      mobGriefing: {
        mobGriefing: {
          'minecraft:villager': 'TRUE',
          'minecraft:wither': 'FALSE',
          'minecraft:ender_dragon': 'FALSE',
        },
      },
    }, '  '),
  },
}
