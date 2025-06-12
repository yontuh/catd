## How to Use
### NixOS
Add:
**1. Add the Flake as an Input**

```nix
# usually /etc/nixos/flake.nix
{
  inputs = {
# add:
    catd = {
      url = "github:yontuh/catd";
    };
  };
  
  # Make sure to add `catd` to the function arguments
  outputs = { self, nixpkgs, catd, ... }@inputs: {
    nixosConfigurations.your-machine-name = nixpkgs.lib.nixosSystem {
      specialArgs = { inherit inputs; }; 
      modules = [ ./configuration.nix ];
    };
  };
}
```

**2. Use the Package**

```nix
# usually /etc/nixos/configuration.nix
{ config, pkgs, inputs, ... }: # Ensure 'inputs' is here

{
  environment.systemPackages = with pkgs; [
    inputs.catd.packages.${pkgs.system}.catd
  ];
}
```

**3. Rebuild **
