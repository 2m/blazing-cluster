{
  description = "chirpstack-network-server flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { ... }@inputs:
    {
      nixosModules.chirpstack-network-server = ../../modules/chirpstack-network-server/module.nix;
      nixosModules.chirpstack-gateway-bridge = ../../modules/chirpstack-gateway-bridge/module.nix;
    };
}
