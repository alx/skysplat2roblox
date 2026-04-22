--[[
  WorldConfig.lua — ModuleScript
  Populated at build time by pipeline/rbxlx_builder.py from world_meta.json.
  All Lua scripts require() this to get world dimensions and scale factors.

  This default config is for a 2048×2048 stud world (512×512 voxels at 4 studs/cell).
  The builder will replace this with values from your actual drone capture.
--]]

return {
  source_bounds = {
    x = {-50, 50},
    y = {-5, 15},
    z = {-50, 50},
  },

  resolution = 512,

  roblox = {
    studs_per_cell     = 4,
    world_width_studs  = 2048,
    world_depth_studs  = 2048,
    world_height_studs = 512,
    terrain_x_origin   = -1024,
    terrain_y_origin   = 0,
    terrain_z_origin   = -1024,
  },

  scale = {
    world_unit_to_stud_x = 20.48,
    world_unit_to_stud_y = 25.6,
    world_unit_to_stud_z = 20.48,
  },
}
