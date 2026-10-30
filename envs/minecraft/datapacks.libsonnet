local packs = {
  cobble_mixer: {
    description: 'Cobblestone mixing recipe',
    files: {
      'data/create/recipe/mixing/cobble_mixer.json': {
        type: 'create:mixing',
        heat_requirement: 'none',
        // Fabric's 40500 units were half a bucket; NeoForge uses 1000 mB per bucket
        ingredients: [
          { type: 'neoforge:single', fluid: 'minecraft:water', amount: 500 },
          { type: 'neoforge:single', fluid: 'minecraft:lava', amount: 500 },
        ],
        results: [{ id: 'minecraft:cobblestone', count: 64 }],
      },
    },
  },
  more_wrench_pickups: {
    description: 'More wrench pickups',
    files: {
      'data/create/tags/block/wrench_pickup.json': {
        replace: false,
        values: [
          'storagedrawers:controller',
          // Storage Drawers 13 uses controller_io instead of controller_slave
          'storagedrawers:controller_io',
          'storagedrawers:compacting_drawers_2',
          'storagedrawers:compacting_drawers_3',
          'storagedrawers:compacting_half_drawers_2',
          'storagedrawers:compacting_half_drawers_3',
          '#storagedrawers:full_drawers',
          '#storagedrawers:half_drawers',
          '#storagedrawers:trim',
        ],
      },
    },
  },
  xp_packing: {
    description: 'Recipe for experience nuggets',
    files: {
      'data/create/recipe/compacting/xp_nuggets.json': {
        type: 'create:compacting',
        heat_requirement: 'superheated',
        ingredients: [{ item: 'minecraft:infested_stone' }],
        results: [{ id: 'create:experience_nugget', count: 1, chance: 0.1 }],
      },
    },
  },
};

// Minecraft accepts directory datapacks; the image's native config sync copies these before launch
std.foldl(
  function(files, name)
    files
    {
      ['world/datapacks/' + name + '/pack.mcmeta']: std.manifestJsonEx({
        pack: { pack_format: 48, description: packs[name].description },
      }, '  '),
    }
    + {
      ['world/datapacks/' + name + '/' + path]: std.manifestJsonEx(packs[name].files[path], '  ')
      for path in std.objectFields(packs[name].files)
    },
  std.objectFields(packs),
  {}
)
