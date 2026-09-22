{ pkgs, ... }:
{
  environment.systemPackages = [ pkgs.blender pkgs.godotPackages_4_7.godot ];
}
